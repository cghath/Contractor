class_name BodyDeform
extends Node
## Procedural body damage (Captain, 2026-10-16: "the wounds are really engaging but we also need
## something else there, maybe more body deform?" ... "the body deform stuff should be
## procedural"): every hole a round makes is carved out of the hit part's own voxels, not drawn
## from pre-made damage. An entry knocks out a ragged crater; an exit blows out a bigger one.
## Each crater's edge is torn, its shape jagged by a noise seeded from the spot, so no two match
## and every peer carves the same ones.
##
## Piece by piece (Captain: "it takes a lot of 556 to lose an arm, or head but not as much 308,
## injuries can still be packed and such so dont make it too extreme until after someone is
## dead"): each round scores its energy on the part it hit (Vitals.round_damage: 5.56 ~1, .308 and
## 7.62x54R ~2, .338 ~4; a .50 just kills, Vitals.LETHAL_J). Craters size to it and widen as the
## part's score climbs, so a limb visibly tears up before it goes. Alive, a limb comes off only
## when the host tears it off (gunfire_cut, GUNFIRE: the living take more), as
## an arterial "amputation" bleed a tourniquet stops, so a good medic can save him. Dead, the
## round that takes a part past SEVER_DEAD cuts it, and the head can go (HEAD_DEAD). The cut is where the
## craters are; SEVER_SLAB voxels are torn away and everything past the cut (the rest of the part
## and what it carries: shin and boot, forearm and glove) drops as one loose piece. All of it from
## the replicated wounds (part, "at"/"out", round class) and Vitals.is_dead, so every peer cuts
## the same limb at the same place.
##
## Blast gore (Captain, 2026-10-20: "more realistic dismemberment and body wounds"): BlastGore, on
## the host, records what blasts, .50s and vehicles do (Vitals.gore_list: torn craters, fragment
## pepper, charring, severed and hanging limbs, a body gibbed), and this carves it like the rounds.
## - Inside: a crater's walls and a stump go skin (torn, bloody), then a thin layer of fat, red
##   flesh, and white bone at a limb's core (the skull under the scalp, ribs in the torso), from
##   each part's own shape (profile). Bone sticks out of a stump a little. Visible-devices shows
##   bone at an open fracture on the living; stumps and the dead are here.
## - Hanging by tissue: at GUNFIRE's dangle share of a limb's sever score (or a blast
##   that mangled a thigh or upper arm, BlastGore's "d"), the limb is cut through but for a strip
##   of tissue on one side and the rest of it hangs off at DANGLE_DEG. Cut through later, the
##   hanging part is what drops.
## - Pieces in the same place for everyone: the host settles each piece (SeveredPiece) and records
##   where it lies in its "s" entry; the others fly the same launch and then put it there; a late
##   joiner or a body back from a save gets it lying there. Each piece's collider is fitted to its
##   voxels. A helmet on a head that comes off falls beside it as a real item (BlastGore.drop_helmet).
## - The ragdoll loses what was cut (Ragdoll.cut): no corpse propped up on a limb that's gone.
## - The gore setting (GameSettings.gore: full, reduced, off) is only how this peer draws it.
##
## The first hole on a part gives that soldier their own raster of it (VoxelArt.raster_copy);
## later holes carve the same raster. Rasterising, carving and meshing run on a worker thread
## (a 0.5 cm part is tens of ms); the mesh goes on when it's done, at most MESH_PER_FRAME a frame
## across every body. With every wound gone (reset, respawn) the parts go back to the shared mesh,
## hidden parts show again, pieces go.

## Crater radius in the body's 0.5 cm voxels, and how far the jagged edge strays from it.
const ENTRY_R := 2.4
const EXIT_R := 4.6
const JAG := 0.45
## The torn-flesh rim round each crater, in voxels.
const RIM := 1.6
## How far in from the skin a crater is centred (voxels): it bites into the part.
const SINK := 1.0
## A round's crater size by class, and how much wider craters get on a part that's taken a lot
## (up to WIDEN at the part's sever score) and on the dead (DEAD_SIZE).
const CLASS_SIZE := {&"pistol": 0.8, &"intermediate": 1.0, &"full_power": 1.5, &"fragment": 0.7}
const WIDEN := 0.6
const DEAD_SIZE := 1.25
## Points a round scores on the part it hits, by class (unknown: intermediate).
const DAMAGE := {&"pistol": 0.5, &"intermediate": 1.0, &"full_power": 2.5, &"fragment": 0.6}
## Gunfire takes limbs (Captain, 2026-10-21: "shot this dude over 40 times with the 1014 and his
## legs didnt come off. more than 20 rounds per leg"; 2026-10-16: "it takes a lot of 556 to lose
## an arm, or head but not as much 308"). Every hit scores points on the part it hits
## (Vitals.round_damage -> hit_points): (energy / Vitals.DAMAGE_J) ^ "exponent" x the round class's
## "class_mult", so heavy rounds count far more than light ones; a buckshot pellet scores linearly
## x "pellet_mult" (nine of them a shell, chewing). Past a part's "points" it comes off, alive or
## dead, decided on the host (gunfire_cut, from Vitals.server_hit) and sent like a blast's cut
## (BlastGore: a synced piece): hands and feet first (hits in the lowest "extremity_share" of a
## forearm or shin score apart and take it at the wrist or ankle), then forearms and shins
## ("distal"), then upper arms and thighs ("proximal", the shin or forearm going with it); the head
## only once he's dead. The living take "alive_mult" times as much, and a limb lost alive is an
## arterial amputation and shock (Vitals.server_amputate). Short of the cut, at "dangle_share" of
## it a limb hangs by tissue (the living's only with a broken bone). One table, all Proposed:
## "round_mult" scales cartridges on their own (rounds.json ids, by prefix): Captain, 2026-10-21:
## "lower 762x54rs ability to dismember" ... "lower those too if theyre close to that 54r", so
## 7.62x54R and the full-power rounds near its ~3.3 kJ (7.62x51 M80, M993 and M118LR, .30-06,
## 6.5 Creedmoor, .303) score half: up close (2.4) about 4 into a living forearm or shin, 7 into a
## dead thigh. A 5.56 (1 point): about 10 into a living shin, 20 into a thigh; .338 (12): 1; a .50 (Vitals.LETHAL_J) kills and takes what it hits; 00 buckshot
## close (0.7 a pellet, ~4 a shell on a leg): 2 or 3 shells for a shin, 5 for a thigh; a 9 mm
## (0.13): only sustained fire into one joint.
const GUNFIRE := {
	"exponent": 1.5,
	"class_mult": {&"pistol": 0.8, &"intermediate": 1.0, &"full_power": 1.5, &"fragment": 0.6},
	"pellet_mult": 4.0,
	"round_mult": {"762x54r": 0.5, "762x51": 0.5, "3006": 0.5, "65cm": 0.5, "303": 0.5},
	"points": {"extremity": 5.0, "distal": 8.0, "proximal": 16.0, "head": 7.0},
	"alive_mult": 1.2,
	"extremity_share": 0.35,
	"dangle_share": 0.75,
}
## (Older names, for what reads them.)
const SEVER_DEAD := 16.0
const HEAD_DEAD := 7.0
const SEVER_SLAB := 2
## A head comes off this many voxels up from the bottom of its neck (the neck is ~18 tall): a
## neck stump stands on the collar (Captain, 2026-10-21: "theres no model for a neck").
const NECK_STUMP := 11.0
## Proposed: hanging by tissue at this share of the sever score (dead; DANGLE_ALIVE alive, its bone
## broken too), the hanging part at DANGLE_DEG off the stump; the strip left is DANGLE_BRIDGE of
## the part's width.
const DANGLE_SHARE := 0.75
const DANGLE_ALIVE := 0.85
const DANGLE_DEG := 40.0
const DANGLE_BRIDGE := 0.3
const LIMBS: Array[StringName] = [Vitals.THIGH_L, Vitals.THIGH_R, Vitals.SHIN_L, Vitals.SHIN_R,
	Vitals.UPPER_ARM_L, Vitals.UPPER_ARM_R, Vitals.FOREARM_L, Vitals.FOREARM_R]
const HEAD_PARTS: Array[StringName] = [Vitals.HEAD, Vitals.FACE]
## The part a limb part hangs from (cut there, this one goes with it).
const PARENT_PART := {Vitals.SHIN_L: Vitals.THIGH_L, Vitals.SHIN_R: Vitals.THIGH_R,
	Vitals.FOREARM_L: Vitals.UPPER_ARM_L, Vitals.FOREARM_R: Vitals.UPPER_ARM_R}
## Craters a part takes before more stop changing it.
const MAX_PER_PART := 18
## A loose piece's push off the body, and how many lie about per body and in the world at most.
const PIECE_PUSH := 1.4
const MAX_PIECES := 5
const MAX_PIECES_WORLD := 40
const PIECE_LIFE_S := Vector2(360.0, 420.0)
## Inside a part (inner): out from the core, as a share of the part's own half-width per layer:
## bone below BONE_SHARE (a limb), fat past FAT_SHARE, the surface (skin, cloth) past SKIN_SHARE;
## the skull from SKULL_SHARE, the ribs from RIB_SHARE every RIB_EVERY layers (RIB_THICK of them).
const BONE_SHARE := 0.24
const FAT_SHARE := 0.8
const SKIN_SHARE := 0.9
const SKULL_SHARE := 0.74
const RIB_SHARE := 0.66
const RIB_EVERY := 5
const RIB_THICK := 2
## How far bone sticks out of a stump past the torn flesh (layers).
const BONE_OUT := 2
## Fragment pocks: radius (voxels) and their rim.
const POCK_R := Vector2(0.7, 1.3)
const POCK_RIM := 1.0
## Part kinds (inner).
const K_LIMB := 0
const K_HEAD := 1
const K_TORSO := 2
## Meshes put on per frame, every body together (a 0.5 cm part's mesh is a few ms).
const MESH_PER_FRAME := 3
## How often the gore setting is looked at (s).
const SETTING_POLL_S := 1.0

## Tests: forces the gore level ("full", "reduced", "off"); "" follows GameSettings.gore.
static var gore_override := ""
static var _budget_frame := -1
static var _budget_left := 0
static var _world_pieces: Array = []  # every peer's loose pieces, oldest first (MAX_PIECES_WORLD)

var model: CharacterModel
var vitals: Vitals
var body := ""
var _done := {}       # hole key -> true (carved)
var _seen := {}       # hole key -> true (counted: a round is "fresh" once, drawn or not)
var _parts := {}      # part pivot (Node3D) -> {"buffer", "model", "variant", "todo", "busy", "count", "ys", "profile", "kind", "gen"}
var _score := {}      # part -> points (DAMAGE)
var _severed := {}    # part -> true: cut off (whatever this peer draws)
var _dangled := {}    # part -> true: hanging by tissue
var _cut_drawn := {}  # part -> true: its cut queued on the mesh
var _dangle_drawn := {}  # part -> the hinge (Node3D) its hanging part is drawn on, or true while queued
var _sever_rec := {}  # part -> its gore "s" entry (where it was cut, its launch and rest pose)
var _dangle_rec := {} # part -> its gore "d" entry
var _gore_done := {}  # gore entry id -> true (carved)
var _pieces: Array[Node3D] = []   # loose pieces in the world
var _piece_of := {}   # part -> its SeveredPiece
var _hidden: Array[Node3D] = []   # parts hidden because they went with a piece
var _tasks: Array[int] = []  # worker tasks not waited for yet (WorkerThreadPool wants every one waited for, or the game can't quit)
var _pending: Array = []  # worker results waiting for a meshing slot (MESH_PER_FRAME)
var _level := ""      # the gore level drawn with
var _poll := 0.0
var _recording := {}  # host: part -> true, its "s" entry on its way (_record_severs)

## A part's mesh was cut through (a piece dropped, pulped or left hanging): what's drawn on it changes
## (WoundMarks keeps only the marks on what's left).
signal reshaped
## How far outside a cut part's mesh a wound mark may sit and still be drawn (cut_bounds).
const MARK_MARGIN := 0.015


func setup(p_model: CharacterModel, p_vitals: Vitals) -> void:
	model = p_model
	vitals = p_vitals
	body = BodyVolume.body_of(p_model)
	vitals.changed.connect(_rebuild)
	var marks := model.get_node_or_null(^"WoundMarks")
	if marks and marks.has_method(&"on_reshaped"):
		reshaped.connect(marks.on_reshaped)
	_rebuild()


## What's left of cut or hanging `part` (its pivot's space, MARK_MARGIN round its mesh), or null
## while it's whole (Captain, 2026-10-21: "blood marks on a body stay where a limb was after it
## dismembers": WoundMarks draws only the marks inside it).
func cut_bounds(part: StringName) -> Variant:
	if not (_severed.has(part) or _dangled.has(part)):
		return null
	var mi := _mesh_of(model.part_node(part))
	if mi == null or mi.mesh == null or not _parts.has(model.part_node(part)) or (_parts[model.part_node(part)] as Dictionary).buffer == null:
		return null
	return (mi.transform * mi.get_aabb()).grow(MARK_MARGIN)


## The gore level this peer draws: "full", "reduced" or "off".
static func gore_level() -> String:
	return gore_override if gore_override != "" else GameSettings.gore()


## Craters carved on `part` so far (tests, debug).
func craters_on(part: StringName) -> int:
	var pivot := model.part_node(part) if model else null
	return int((_parts.get(pivot, {}) as Dictionary).get("count", 0))


## Points `part` has taken (DAMAGE), and the limbs / head cut off so far.
func score_of(part: StringName) -> float:
	return float(_score.get(_bone_part(part), 0.0))


func severed() -> Array:
	return _severed.keys()


## Limbs hanging by tissue (not cut through yet).
func dangling() -> Array:
	return _dangled.keys().filter(func(p: StringName) -> bool: return not _severed.has(p))


func pieces() -> Array[Node3D]:
	return _pieces


## The piece `part` became, or null.
func piece_of(part: StringName) -> SeveredPiece:
	var p: Variant = _piece_of.get(part)
	return p as SeveredPiece if is_instance_valid(p) else null


## How much of `part` stays on the body as a stump (0..1 of its length; 0 for the head).
func stump_of(part: StringName) -> float:
	if part == Vitals.HEAD or not BodyMap.PART_BOXES.has(part):
		return 0.0
	var rec: Dictionary = _sever_rec.get(part, {})
	var at: Variant = BlastGore.to_vec(rec.get("a"))
	if at == null:
		return 0.5
	var box: Array = BodyMap.PART_BOXES[part][0]
	var top: float = (box[0] as Vector3).y + (box[1] as Vector3).y * 0.5
	return clampf((top - (at as Vector3).y) / maxf((box[1] as Vector3).y, 0.01), 0.15, 0.9)


## Every part cut off `vitals`' body by the record (gore "s" entries; amputations, but for a limb
## left hanging), with what went with each (a shin with its thigh). The host's view, for BlastGore.
static func severed_parts(p_vitals: Vitals) -> Array[StringName]:
	var out: Array[StringName] = []
	var hanging := {}
	for g: Dictionary in p_vitals.gore_list():
		if String(g.get("k", "")) == "d":
			hanging[StringName(g.p)] = true
	for g: Dictionary in p_vitals.gore_list():
		if String(g.get("k", "")) == "s" and not StringName(g.p) in out:
			out.append(StringName(g.p))
	for w: Dictionary in p_vitals.wound_list():
		if w.get("name") == Vitals.AMPUTATION and not hanging.has(w.part) and not w.part in out:
			out.append(w.part)
	for child: StringName in PARENT_PART:
		if PARENT_PART[child] in out and not child in out:
			out.append(child)
	return out


## What a zone save keeps of `p_vitals`' body (Soldier.body_record "gore"): its holes as
## [part, at, out, round class, points] and its gore entries. Vitals.server_restore_gore puts it back.
static func save_record(p_vitals: Vitals) -> Dictionary:
	var marks: Array = []
	var seen := {}
	for w: Dictionary in p_vitals.wound_list():
		var at: Variant = w.get("at")
		if not at is Vector3:
			continue
		var key := "%s%s" % [w.part, at]
		if seen.has(key):
			continue
		seen[key] = true
		var out: Variant = w.get("out")
		marks.append([String(w.part), BlastGore.vec(at), BlastGore.vec(out) if out is Vector3 else [], String(w.get("round_class", &"")),
			snappedf(_points(w, StringName(w.get("round_class", &""))), 0.1)])
	return {"m": marks, "z": p_vitals.gore_list().duplicate(true)}


func _process(delta: float) -> void:
	_drain()
	_poll -= delta
	if _poll <= 0.0:
		_poll = SETTING_POLL_S
		if _level != "" and gore_level() != _level:
			_rebuild()


func _rebuild() -> void:
	if not is_instance_valid(vitals) or not is_instance_valid(model):
		return
	var level := gore_level()
	if level != _level:
		if _level != "":
			_clear_visuals()
		_level = level
	var draw := level != "off"
	var dead := vitals.is_dead()
	var any := false
	var score := {}
	var broken := {}
	var counted := {}
	var ats := {}  # part -> rest-pose points its rounds went in (where a cut goes)
	var amputated := {}  # part -> true: the host tore it off (Vitals.AMPUTATION)
	var fresh := false  # a round landed since last time
	for w: Dictionary in vitals.wound_list():
		var part := _bone_part(w.part)
		if String(w.kind) == "fracture":
			broken[part] = true
		if w.get("name") == Vitals.AMPUTATION:
			amputated[part] = true
		var at: Variant = w.get("at")
		if not at is Vector3:
			continue
		any = true
		var rc := StringName(w.get("round_class", &""))
		var key := "%s%s" % [w.part, at]
		if not counted.has(key):  # one round, however many wounds it made
			counted[key] = true
			score[part] = float(score.get(part, 0.0)) + _points(w, rc)
			if not ats.has(part):
				ats[part] = []
			(ats[part] as Array).append(at)
			if not _seen.has(key):
				_seen[key] = true
				fresh = true
		if _done.has(key) or not draw:
			continue
		_done[key] = true
		_score = score.duplicate()  # craters size to the damage so far (this round included)
		var size := _crater_size(w, rc) * (DEAD_SIZE if dead else 1.0) * (1.0 + WIDEN * clampf(float(score.get(part, 0.0)) / _threshold(part, dead), 0.0, 1.0))
		_queue(w.part, at, false, size)
		var out: Variant = w.get("out")
		if out is Vector3:
			_queue(w.part, out, true, size)
	_score = score
	var gore := vitals.gore_list()
	if not any and gore.is_empty():
		if not _done.is_empty() or not _severed.is_empty() or not _dangled.is_empty() or not _gore_done.is_empty():
			_restore()
		return
	for g: Dictionary in gore:
		var kind := String(g.get("k", ""))
		var part := StringName(g.get("p", ""))
		if kind == "s":
			_sever_rec[part] = g
			var piece := piece_of(part)
			if piece and (g.get("q", []) as Array).size() == 7:
				piece.settle_to(g.q)
		elif kind == "d":
			_dangle_rec[part] = g
		var id := int(g.get("i", 0))
		if _gore_done.has(id) or not draw:
			continue
		_gore_done[id] = true
		match kind:
			"c":
				var at: Variant = BlastGore.to_vec(g.get("a"))
				if at != null:
					_queue(part, at, true, float(g.get("r", 1.0)))
			"p":
				if level == "full":
					_queue_effect(part, {"pepper": int(g.get("n", 1)), "dir": BlastGore.to_vec(g.get("d")), "salt": int(g.get("s", 0))})
			"h":
				_queue_effect(part, {"char": float(g.get("m", 0.5)), "dir": BlastGore.to_vec(g.get("d")), "salt": id * 7919})
	# What comes off and what hangs: the record (the host's blasts and cuts, amputations), and for
	# the dead the round that tipped a part (the host records it for the rest).
	var new_cuts: Array[StringName] = []
	for part: StringName in LIMBS + [Vitals.HEAD]:
		if _severed.has(part) or _ancestor_severed(part):
			continue
		var limit := _threshold(part, dead)
		var points := float(score.get(part, 0.0))
		# (Gunfire's cuts are the host's, from every hit so far: gunfire_cut, recorded like a blast's.)
		var cut := _sever_rec.has(part) or (amputated.has(part) and not _dangle_rec.has(part))
		if cut:
			_severed[part] = true
			new_cuts.append(part)
			if not _sever_rec.has(part) and _is_host():
				_sever_rec[part] = _bullet_sever(part, ats.get(part, []))
				_recording[part] = true
			continue
		if part != Vitals.HEAD and not _dangled.has(part) and (_dangle_rec.has(part)
				or ((dead or broken.has(part)) and points >= limit * float(GUNFIRE.dangle_share) and limit < INF)):
			_dangled[part] = true
	for part: StringName in new_cuts:
		_cut_ragdoll(part)
	if not _recording.is_empty():
		_record_severs.call_deferred()
	if not draw:
		return
	for part: StringName in _severed:
		if not _cut_drawn.has(part) and not _ancestor_severed(part):
			_cut_drawn[part] = true
			_queue_sever(part, ats.get(part, []))
	for part: StringName in _dangled:
		if not _dangle_drawn.has(part) and not _severed.has(part) and not _ancestor_severed(part):
			_dangle_drawn[part] = true
			_queue_dangle(part, ats.get(part, []))


## Host: the "s" entries for cuts this peer decided from the rounds (sent after _rebuild, which
## the publish would otherwise re-enter).
func _record_severs() -> void:
	if not is_instance_valid(vitals):
		return
	var known := {}
	for g: Dictionary in vitals.gore_list():
		if String(g.get("k", "")) == "s":
			known[StringName(g.p)] = true
	var parts: Array = _recording.keys()
	_recording.clear()
	for part: StringName in parts:
		if known.has(part) or not _sever_rec.has(part):
			continue
		BlastGore.drop_helmet(vitals, part)
		var id := vitals.server_gore_add(_sever_rec[part], false)
		(_sever_rec[part] as Dictionary)["i"] = id
	vitals.server_gore_flush()


## An "s" entry for a cut the rounds made: cut where they went in, a small push off the body.
func _bullet_sever(part: StringName, at_list: Array) -> Dictionary:
	var rec := {"k": "s", "p": String(part)}
	if not at_list.is_empty():
		var sum := Vector3.ZERO
		for a: Vector3 in at_list:
			sum += a
		rec["a"] = BlastGore.vec(sum / at_list.size())
	var launch := _default_launch(part)
	rec["v"] = BlastGore.vec(launch[0], 0.01)
	rec["w"] = BlastGore.vec(launch[1], 0.01)
	return rec


## [velocity, spin] for a piece cut by rounds: off the body sideways, a little up.
func _default_launch(part: StringName) -> Array:
	var pivot := model.part_node(part)
	var away := (pivot.global_position - model.global_position) if pivot and pivot.is_inside_tree() else Vector3.FORWARD
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s%s" % [vitals.get_parent().name if vitals.get_parent() else "", part])
	return [(away * PIECE_PUSH + Vector3.UP * 0.6) * 0.5, Vector3(r.randf() - 0.5, r.randf() - 0.5, r.randf() - 0.5) * 0.6]


## What a round scored on its part: its energy (Vitals.round_damage: 5.56 ~1, 7.62x51 and x54R
## ~2, .338 ~4, .50 ~10), else by class (DAMAGE).
static func _points(w: Dictionary, rc: StringName) -> float:
	var dmg := float(w.get("dmg", 0.0))
	return dmg if dmg > 0.0 else float(DAMAGE.get(rc, DAMAGE[&"intermediate"]))


## A round's crater size: bigger with its energy (a 5.56 1, a .308 ~1.3, capped at 2.2), else by class.
static func _crater_size(w: Dictionary, rc: StringName) -> float:
	var dmg := float(w.get("dmg", 0.0))
	return clampf(0.7 + 0.3 * dmg, 0.7, 2.2) if dmg > 0.0 else float(CLASS_SIZE.get(rc, 1.0))

## Points at which `part` comes off (GUNFIRE), whole (its hand or foot sooner: gunfire_cut).
static func _threshold(part: StringName, dead: bool) -> float:
	var pts: Dictionary = GUNFIRE.points
	if part == Vitals.HEAD:
		return float(pts.head) if dead else INF
	return float(pts.distal if part in BlastGore.DISTAL else pts.proximal) * (1.0 if dead else float(GUNFIRE.alive_mult))


## What one hit scores (GUNFIRE): from its energy on arrival (joules; <= 0 unknown: by class), a
## buckshot `pellet` linearly, times its cartridge's own "round_mult" (`round_id`, rounds.json).
static func hit_points(round_class: StringName, energy_j: float, pellet := false, round_id := "") -> float:
	if energy_j <= 0.0:
		return float(DAMAGE.get(round_class, DAMAGE[&"intermediate"]))
	var base := energy_j / Vitals.DAMAGE_J
	var own := 1.0
	for prefix: String in GUNFIRE.round_mult:
		if round_id.begins_with(prefix):
			own = float(GUNFIRE.round_mult[prefix])
	if pellet:
		return base * float(GUNFIRE.pellet_mult) * own
	return pow(base, float(GUNFIRE.exponent)) * float((GUNFIRE.class_mult as Dictionary).get(round_class, 1.0)) * own


## Host: the cut the hits so far make on `part`'s bone (a limb part, or the head once `dead`), from
## `wounds` (WoundModel's: each round's "at" and points "dmg"): {} for none yet, else {"part", "at":
## where it's cut (rest pose; a hand or foot at the wrist or ankle; null for the head)}. GUNFIRE.
static func gunfire_cut(wounds: Array, part: StringName, dead: bool) -> Dictionary:
	var bone := _bone_part(part)
	if not (bone in LIMBS or (bone == Vitals.HEAD and dead)):
		return {}
	var distal := bone in BlastGore.DISTAL
	var ext_top := -INF
	if distal:
		var box: Array = BodyMap.PART_BOXES[bone][0]
		var bottom: float = (box[0] as Vector3).y - (box[1] as Vector3).y * 0.5
		ext_top = bottom + (box[1] as Vector3).y * float(GUNFIRE.extremity_share)
	var total := 0.0
	var low := 0.0
	var sum := Vector3.ZERO
	var low_sum := Vector3.ZERO
	var n := 0
	var nl := 0
	var seen := {}
	for w: Dictionary in wounds:
		var at: Variant = w.get("at")
		if _bone_part(w.part) != bone or not at is Vector3:
			continue
		var key := "%s%s" % [w.part, at]
		if seen.has(key):
			continue  # one round, however many wounds it made
		seen[key] = true
		var pts := _points(w, StringName(w.get("rc", &"")))
		total += pts
		sum += at
		n += 1
		if distal and (at as Vector3).y <= ext_top:
			low += pts
			low_sum += at
			nl += 1
	if n == 0:
		return {}
	var mult := 1.0 if dead else float(GUNFIRE.alive_mult)
	if distal and nl > 0 and low >= float(GUNFIRE.points.extremity) * mult:
		var a := low_sum / nl
		return {"part": bone, "at": Vector3(a.x, ext_top, a.z)}  # the hand or foot, at the wrist or ankle
	if total >= _threshold(bone, dead):
		return {"part": bone, "at": sum / n if bone != Vitals.HEAD else null}
	return {}


## The part whose bone carries `part` (face and neck hits count on the head).
static func _bone_part(part: StringName) -> StringName:
	return Vitals.HEAD if part in HEAD_PARTS or part == Vitals.NECK else part


## Whether the part `part` hangs from is cut off (a shin when the thigh went).
func _ancestor_severed(part: StringName) -> bool:
	return PARENT_PART.has(part) and _severed.has(PARENT_PART[part])


## Whether `part` already went with a piece (or hangs) cut off above it.
func _gone(part: StringName) -> bool:
	var pivot := model.part_node(part)
	if pivot == null:
		return true
	var n: Node = pivot
	while n != null and n != model:
		if n in _hidden:
			return true
		n = n.get_parent()
	return false


func _is_host() -> bool:
	return not is_inside_tree() or multiplayer.multiplayer_peer == null or multiplayer.is_server()


## The ragdoll (host's or following) drops the part's colliders (Ragdoll.cut).
func _cut_ragdoll(part: StringName) -> void:
	var soldier := model.get_parent() as Soldier if is_instance_valid(model) else null
	if soldier and is_instance_valid(soldier.ragdoll):
		soldier.ragdoll.cut(part, stump_of(part))


## Every carved part back to the shared mesh, hidden parts shown, pieces gone (wounds reset).
func _restore() -> void:
	_clear_visuals()
	_seen.clear()
	_score.clear()
	_severed.clear()
	_dangled.clear()
	_sever_rec.clear()
	_dangle_rec.clear()
	_recording.clear()


## Everything drawn goes (pieces, hanging parts, carved meshes); what's cut stays known, so a
## rebuild draws it again (the gore setting changed).
func _clear_visuals() -> void:
	_done.clear()
	_gore_done.clear()
	_cut_drawn.clear()
	for hinge: Variant in _dangle_drawn.values():
		if hinge is Node and is_instance_valid(hinge):
			(hinge as Node).queue_free()
	_dangle_drawn.clear()
	for piece in _pieces:
		if is_instance_valid(piece):
			piece.queue_free()
	_pieces.clear()
	_piece_of.clear()
	for part_node in _hidden:
		if is_instance_valid(part_node):
			part_node.visible = true
	_hidden.clear()
	_pending.clear()
	for pivot: Node3D in _parts.keys():
		var state: Dictionary = _parts[pivot]
		state.todo.clear()
		state.count = 0
		state.ys = []
		state.buffer = null
		state.gen = int(state.gen) + 1
		var mi := _mesh_of(pivot)
		if mi:
			mi.mesh = VoxelArt.mesh(state.model, state.variant)


func _state_for(pivot: Node3D) -> Dictionary:
	var state: Dictionary = _parts.get(pivot, {})
	if state.is_empty():
		var m := String(pivot.get_meta(&"voxel_model"))
		state = {"buffer": null, "model": m, "variant": String(pivot.get_meta(&"voxel_variant", "")),
			"todo": [], "busy": false, "count": 0, "ys": [], "profile": PackedFloat32Array(), "gen": 0,
			"kind": K_HEAD if m.begins_with("head") else (K_TORSO if m.begins_with("torso") else K_LIMB)}
		_parts[pivot] = state
	return state


## A rest-pose body point on `part` in its raster's voxels (no skin search).
func _raster_point(part: StringName, at: Vector3) -> Vector3:
	var pivot := model.part_node(part)
	var mi := _mesh_of(pivot)
	if mi == null:
		return Vector3.ZERO
	return (at - BodyVolume.pivot_at(part, body) - mi.position) / mi.scale.x + Vector3.ONE


## A rest-pose direction in the part's raster.
static func _raster_dir(mi: MeshInstance3D, dir: Variant) -> Vector3:
	if not dir is Vector3 or (dir as Vector3).length_squared() < 0.0001:
		return Vector3.FORWARD
	return (mi.basis.inverse() * (dir as Vector3)).normalized()


func _queue(part: StringName, at: Vector3, exit: bool, size: float) -> void:
	var pivot := model.part_node(part)
	var mi := _mesh_of(pivot)
	if mi == null or not pivot.has_meta(&"voxel_model") or _gone(part):
		return
	var state := _state_for(pivot)
	if int(state.count) >= MAX_PER_PART:
		return
	state.count = int(state.count) + 1
	# Rest-pose body point -> the part's mesh voxels (as WoundMarks places its marks on the bone).
	var n := WoundMarks._outward(part, at)
	var skin: Variant = BodyVolume.surface(part, at, n, 0.05, body)
	var p: Vector3 = (skin if skin is Vector3 else at) - BodyVolume.pivot_at(part, body)
	var wide := mi.scale / mi.scale.y  # a build's girth (CharacterModel.girth): the mesh is widened, the rest pose isn't
	var centre := (p * wide - mi.position) / mi.scale + Vector3.ONE  # +1: the raster's mesher padding
	var inward := -(mi.basis.inverse() * n).normalized()
	(state.ys as Array).append(centre.y)
	state.todo.append({"centre": centre + inward * SINK, "r": (EXIT_R if exit else ENTRY_R) * size, "salt": hash("%s%s%s" % [part, at, exit])})
	_kick(pivot)


## Pepper or charring on `part` (BlastGore "p" / "h"): `job` with its direction in the raster.
func _queue_effect(part: StringName, job: Dictionary) -> void:
	var pivot := model.part_node(part)
	var mi := _mesh_of(pivot)
	if mi == null or not pivot.has_meta(&"voxel_model") or _gone(part):
		return
	var state := _state_for(pivot)
	if job.has("pepper"):
		if int(state.count) >= MAX_PER_PART:
			return
		state.count = int(state.count) + 1
	job["dir"] = _raster_dir(mi, job.get("dir"))
	state.todo.append(job)
	_kick(pivot)


## Cuts `part` through: where its record says (BlastGore, a recorded cut), else where its craters
## are, the head low on the neck. A hanging part drops as it hangs.
func _queue_sever(part: StringName, at_list: Array) -> void:
	var pivot := model.part_node(part)
	var mi := _mesh_of(pivot)
	if mi == null or not pivot.has_meta(&"voxel_model"):
		return
	var hinge: Variant = _dangle_drawn.get(part)
	if hinge is Node3D and is_instance_valid(hinge):
		_dangle_drawn.erase(part)
		_drop_hanging(part, pivot, mi, hinge as Node3D)
		return
	var state := _state_for(pivot)
	var rec: Dictionary = _sever_rec.get(part, {})
	var cut := -1.0  # worker picks: the head just above its lowest voxels
	if part != Vitals.HEAD:
		cut = _cut_y(part, rec, at_list, state)
	# (Hanging, still on its way to the mesh: what hangs is the piece, not what's left below the cut.)
	var hanging := _dangle_drawn.has(part)
	state.todo.append({"sever": true, "cut": cut, "far_up": part == Vitals.HEAD, "part": part, "drop": not rec.get("np", false) and not hanging})
	_kick(pivot)


## Cuts `part` nearly through, leaving a strip of tissue it hangs by.
func _queue_dangle(part: StringName, at_list: Array) -> void:
	var pivot := model.part_node(part)
	var mi := _mesh_of(pivot)
	if mi == null or not pivot.has_meta(&"voxel_model") or _gone(part):
		return
	var state := _state_for(pivot)
	var rec: Dictionary = _dangle_rec.get(part, {})
	state.todo.append({"dangle": true, "cut": _cut_y(part, rec, at_list, state), "part": part,
		"salt": int(rec.get("s", hash(String(part) + String(vitals.get_parent().name if vitals.get_parent() else ""))))})
	_kick(pivot)


## The raster layer a limb is cut at: its record's point, else the rounds' (else the craters').
func _cut_y(part: StringName, rec: Dictionary, at_list: Array, state: Dictionary) -> float:
	var at: Variant = BlastGore.to_vec(rec.get("a"))
	if at != null:
		return _raster_point(part, at).y
	var ys: Array = state.ys
	if not at_list.is_empty():
		var sum := 0.0
		for a: Vector3 in at_list:
			sum += _raster_point(part, a).y
		return sum / at_list.size()
	if not ys.is_empty():
		var sum := 0.0
		for y: float in ys:
			sum += y
		return sum / ys.size()
	return -2.0  # the middle of the part (the worker finds it)


## Lets go of finished worker tasks; `all` waits for the rest too (leaving the tree).
func _reap(all := false) -> void:
	for task in _tasks.duplicate():
		if all or WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_tasks.erase(task)


func _exit_tree() -> void:
	_reap(true)

## Starts the part's worker if it's idle and has work waiting.
func _kick(pivot: Node3D) -> void:
	var state: Dictionary = _parts.get(pivot, {})
	if state.is_empty() or state.busy or (state.todo as Array).is_empty():
		return
	state.busy = true
	var jobs: Array = state.todo.duplicate()
	state.todo.clear()
	var settings := {"kind": int(state.kind), "bone": _level == "full", "gen": int(state.gen)}
	state.task = WorkerThreadPool.add_task(BodyDeform._work.bind(weakref(self), pivot, state.buffer, state.profile, state.model, state.variant, jobs, settings))
	_tasks.append(state.task)


## Worker thread: (the first time) rasterise the part and take its shape, carve, char, cut.
## Meshing is the main thread's.
static func _work(ref: WeakRef, pivot: Node3D, buffer: VoxelBuffer, prof: PackedFloat32Array, model_name: String, variant: String, jobs: Array, settings: Dictionary) -> void:
	if buffer == null:
		buffer = VoxelArt.raster_copy(model_name, variant)
		prof = profile(buffer)
	var kind := int(settings.kind)
	var bone := bool(settings.bone)
	var facing := {}  # step direction -> _facing list (one scan for char and pepper the same way)
	var out := {"profile": prof, "gen": settings.gen, "pieces": [], "hangs": []}
	for job: Dictionary in jobs:
		if job.get("sever", false):
			var cut := float(job.cut)
			if cut < 0.0:
				cut = _lowest_solid(buffer) + NECK_STUMP if cut > -1.5 else _middle(buffer)
			cut = _clamp_cut(buffer, cut) if not bool(job.far_up) else cut
			# A head comes off at the neck: the stump is opened as a limb is (skin, fat, flesh, the
			# spine at its core), not as the skull is.
			var piece := split(buffer, roundi(cut), bool(job.far_up), prof, K_LIMB if kind == K_HEAD else kind, bone)
			out["cut"] = true
			if bool(job.get("drop", true)):
				(out.pieces as Array).append({"part": job.part, "buffer": piece, "hull": hull_points(piece)})
		elif job.get("dangle", false):
			var cut := float(job.cut)
			cut = _clamp_cut(buffer, _middle(buffer) if cut < 0.0 else cut)
			var hang := dangle_split(buffer, roundi(cut), int(job.salt), prof, kind, bone)
			out["cut"] = true
			if not hang.is_empty():
				hang["part"] = job.part
				hang["hull"] = hull_points(hang.buffer)
				(out.hangs as Array).append(hang)
		elif job.has("pepper") or job.has("char"):
			var key := _step(job.dir)
			if not facing.has(key):
				facing[key] = _facing(buffer, job.dir)
			if job.has("pepper"):
				pepper(buffer, job.dir, int(job.pepper), int(job.salt), prof, kind, bone, facing[key])
				facing.erase(key)  # the pocks changed the surface
			else:
				scorch(buffer, job.dir, float(job.char), int(job.salt), facing[key])
		else:
			carve(buffer, job.centre, float(job.r), int(job.salt), prof, kind, bone)
	BodyDeform._deliver.call_deferred(ref, pivot, buffer, out)  # meshing goes through the renderer: main thread only


## Main thread: hands the worker's result back, unless the body went while it worked.
static func _deliver(ref: WeakRef, pivot: Variant, buffer: VoxelBuffer, out: Dictionary) -> void:
	var me := ref.get_ref() as BodyDeform
	if me and is_instance_valid(me) and is_instance_valid(pivot):
		me._reap()
		me._pending.append([pivot, buffer, out])
		me._drain()


## Meshes what the workers finished, MESH_PER_FRAME a frame across every body; the rest waits.
func _drain() -> void:
	var frame := Engine.get_process_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_budget_left = MESH_PER_FRAME
	while not _pending.is_empty() and _budget_left > 0:
		var item: Array = _pending.pop_front()
		_budget_left -= 1
		if is_instance_valid(item[0]):
			_done_work(item[0], item[1], item[2])


func _done_work(pivot: Node3D, buffer: VoxelBuffer, out: Dictionary) -> void:
	if not _parts.has(pivot):
		return
	var state: Dictionary = _parts[pivot]
	state.busy = false
	if int(out.gen) != int(state.gen):  # drawn over since (reset, the setting changed)
		_kick(pivot)
		return
	state.buffer = buffer
	state.profile = out.profile
	var mesher := VoxelArt.mesher_for(state.model, state.variant)
	var mi := _mesh_of(pivot)
	if mi:
		var mesh := mesher.build_mesh(buffer, [])
		if mesh:
			mi.mesh = mesh
	for h: Dictionary in out.hangs:  # (first: one cut through as it's hung drops as it hangs)
		var hang_mesh: Mesh = mesher.build_mesh(h.buffer, [])
		if hang_mesh and mi:
			_hang(StringName(h.part), pivot, mi, hang_mesh, h)
	for p: Dictionary in out.pieces:
		var piece_mesh: Mesh = mesher.build_mesh(p.buffer, [])
		if piece_mesh and mi and not (p.hull as PackedVector3Array).is_empty():
			_drop(StringName(p.part), pivot, mi, piece_mesh, p.hull)
	for h: Dictionary in out.hangs:
		var hang_mesh: Mesh = mesher.build_mesh(h.buffer, [])
		if hang_mesh and mi:
			_hang(StringName(h.part), pivot, mi, hang_mesh, h)
	if out.get("cut", false):
		reshaped.emit()
	_kick(pivot)


## The cut-off piece as a loose body in the world: the far side of the part's raster plus the
## parts and gear it carries (copied, the originals hidden), flung as its record says.
func _drop(part: StringName, pivot: Node3D, mi: MeshInstance3D, piece_mesh: Mesh, hull: PackedVector3Array) -> void:
	if piece_of(part) != null:
		return  # one piece a part (what hung went already): scraps below the cut aren't another
	var rb := _new_piece(part)
	if rb == null:
		return
	var look := MeshInstance3D.new()
	look.mesh = piece_mesh
	look.material_override = mi.material_override
	look.layers = mi.layers
	look.transform = mi.transform
	rb.add_child(look)
	if part == Vitals.HEAD and model.face_rig:
		model.face_rig.head_severed(look)  # the face goes with the head (FaceRig), none left on the stump
	var cut_y := _pivot_cut_y(mi, hull)
	for i in range(1, pivot.get_child_count()):
		var child := pivot.get_child(i) as Node3D
		if child == null or not child.visible or child is MultiMeshInstance3D or child.name.begins_with("Hang"):
			continue  # wound marks stay with the body
		if _keeps(child, part, cut_y):
			continue
		child.visible = false
		_hidden.append(child)
		if child is VoxelArmor and (child as VoxelArmor).slot == &"helmet":
			continue  # it falls off as an item (BlastGore.drop_helmet)
		rb.add_child(child.duplicate() as Node3D)
	_fit_collider(rb, mi.transform, hull)
	_launch(rb, part, pivot.global_transform)


## Whether `child` of a cut part's pivot stays on the stump: above the cut (an armband high on
## the arm); what's below goes with the piece.
static func _keeps(child: Node3D, part: StringName, cut_y: float) -> bool:
	return part != Vitals.HEAD and not child.has_meta(&"voxel_model") and child.position.y > cut_y + 0.01


## The pivot-space height of a cut from the piece's hull (its top).
static func _pivot_cut_y(mi: MeshInstance3D, hull: PackedVector3Array) -> float:
	var top := -INF
	for p in hull:
		top = maxf(top, (mi.transform * (p - Vector3.ONE)).y)
	return top if top > -INF else 0.0


## A hanging part cut through: what hangs drops as it hangs.
func _drop_hanging(part: StringName, pivot: Node3D, mi: MeshInstance3D, hinge: Node3D) -> void:
	var rb := _new_piece(part)
	if rb == null:
		hinge.queue_free()
		return
	var at := hinge.global_transform
	var hull: PackedVector3Array = hinge.get_meta(&"hull", PackedVector3Array())
	var base: Transform3D = hinge.get_meta(&"base", mi.transform)
	for child in hinge.get_children():
		child.reparent(rb, false)
	hinge.queue_free()
	_fit_collider(rb, base, hull)
	_launch(rb, part, at)


## A new loose piece of `part`, or null (no level to put it in).
func _new_piece(part: StringName) -> SeveredPiece:
	var world := model.get_tree().current_scene if model.is_inside_tree() else null
	var level := CompoundLevel.current(model) if model.is_inside_tree() else null
	var parent: Node = level if level else world
	if parent == null:
		return null
	while _pieces.size() >= MAX_PIECES:
		var old: Node3D = _pieces.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	_world_pieces = _world_pieces.filter(func(p: Variant) -> bool: return is_instance_valid(p))
	while _world_pieces.size() >= MAX_PIECES_WORLD:
		var old: Variant = _world_pieces.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var rb := SeveredPiece.new()
	rb.name = "Severed_%s" % part
	rb.part = part
	rb.host = _is_host()
	rb.set_meta(&"piece_of", model.get_parent())
	parent.add_child(rb)
	_pieces.append(rb)
	_world_pieces.append(rb)
	_piece_of[part] = rb
	return rb


## Puts `rb` where it starts (`at`, the part's place) and lets it fly: at its record's rest pose
## if it has one (a late joiner, a restored body), else with its record's launch.
func _launch(rb: SeveredPiece, part: StringName, at: Transform3D) -> void:
	rb.global_transform = Transform3D(at.basis.orthonormalized(), at.origin)
	# Never against its own body or the pieces that came off it with it (Captain, 2026-10-21, an
	# RPG in the chest: the head and thighs, launched from inside the torso's box, shoved it into a
	# tumble that landed it any way up, not thrown back as the blast threw it). Anyone else's, the
	# ground and the world it lands on as before.
	var soldier := model.get_parent() as Soldier
	if soldier and is_instance_valid(soldier.ragdoll):
		for p: PhysicsBody3D in soldier.ragdoll.parts.values():
			rb.add_collision_exception_with(p)
	for other: Node3D in _pieces:
		if other != rb and is_instance_valid(other) and other is PhysicsBody3D:
			rb.add_collision_exception_with(other as PhysicsBody3D)
	var rec: Dictionary = _sever_rec.get(part, {})
	var pose: Array = rec.get("q", [])
	if pose.size() == 7:
		rb.settle_to(pose, true)
	else:
		var fallback := _default_launch(part)
		var v: Variant = BlastGore.to_vec(rec.get("v"))
		var w: Variant = BlastGore.to_vec(rec.get("w"))
		rb.launch(v if v != null else fallback[0], w if w != null else fallback[1])
		if rb.host:
			var me: WeakRef = weakref(self)
			rb.settled.connect(func(q: Array) -> void:
				var d := me.get_ref() as BodyDeform
				if d and is_instance_valid(d):
					d._piece_settled(part, q))
	var ref: WeakRef = weakref(rb)
	var life := lerpf(PIECE_LIFE_S.x, PIECE_LIFE_S.y, float(absi(hash(String(rb.get_meta(&"piece_of").name if rb.get_meta(&"piece_of") else "") + String(part))) % 1000) / 1000.0)
	rb.get_tree().create_timer(life).timeout.connect(func() -> void:
		var p := ref.get_ref() as Node
		if p and is_instance_valid(p):
			p.queue_free())  # Captain, 2026-10-16: ~6-7 min for most things


## Host: piece `part` came to rest at `q`: recorded, so everyone puts it there.
func _piece_settled(part: StringName, q: Array) -> void:
	if not is_instance_valid(vitals):
		return
	for g: Dictionary in vitals.gore_list():
		if String(g.get("k", "")) == "s" and StringName(g.p) == part:
			vitals.server_gore_set(int(g.i), "q", q)
			return
	var rec: Dictionary = _sever_rec.get(part, {})
	if not rec.is_empty():
		rec["q"] = q  # its entry is on its way (_record_severs): it goes with it


## A collider fitted to the piece: a convex hull of its voxels' outline (hull_points), in the
## piece's space through `base` (the part mesh's transform); a box if it has too few.
static func _fit_collider(rb: RigidBody3D, base: Transform3D, hull: PackedVector3Array) -> void:
	var shape := CollisionShape3D.new()
	if hull.size() >= 4:
		var points := PackedVector3Array()
		for p in hull:
			points.append(base * (p - Vector3.ONE))
		var convex := ConvexPolygonShape3D.new()
		convex.points = points
		shape.shape = convex
	else:
		var box := _bounds(rb)
		var b := BoxShape3D.new()
		b.size = box.size.max(Vector3.ONE * 0.04)
		shape.shape = b
		shape.position = box.get_center()
	rb.add_child(shape)


## A hanging part on the stump: on a hinge at its strip of tissue, swung DANGLE_DEG, with what the
## part carries below the cut (copied, the originals hidden).
func _hang(part: StringName, pivot: Node3D, mi: MeshInstance3D, hang_mesh: Mesh, h: Dictionary) -> void:
	var hinge := Node3D.new()
	hinge.name = "Hang_%s" % part
	pivot.add_child(hinge)
	var at: Vector3 = mi.transform * ((h.hinge as Vector3) - Vector3.ONE)
	var side: Vector3 = (mi.basis * (h.side as Vector3)).normalized()
	var axis := Vector3.DOWN.cross(side).normalized()
	if axis.length() < 0.5:
		axis = Vector3.RIGHT
	hinge.position = at
	hinge.basis = Basis(axis, deg_to_rad(DANGLE_DEG))
	var look := MeshInstance3D.new()
	look.mesh = hang_mesh
	look.material_override = mi.material_override
	look.layers = mi.layers
	look.transform = Transform3D(Basis.IDENTITY, -at) * mi.transform
	hinge.add_child(look)
	hinge.set_meta(&"hull", h.hull)
	hinge.set_meta(&"base", look.transform)
	var cut_y: float = (mi.transform * Vector3(0, float(h.cut) - 1.0, 0)).y
	for i in range(1, pivot.get_child_count()):
		var child := pivot.get_child(i) as Node3D
		if child == null or child == hinge or not child.visible or child is MultiMeshInstance3D or child.name.begins_with("Hang"):
			continue
		if _keeps(child, part, cut_y):
			continue
		var copy := child.duplicate() as Node3D
		hinge.add_child(copy)
		copy.transform = Transform3D(Basis.IDENTITY, -at) * child.transform
		child.visible = false
		_hidden.append(child)
	_dangle_drawn[part] = hinge
	if _severed.has(part):  # cut through while it was being hung: it drops as it hangs
		_dangle_drawn.erase(part)
		_drop_hanging(part, pivot, mi, hinge)


## Every mesh under `root` in its space, merged (empty meshes skipped).
static func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var t: Transform3D = item[1]
		for child in node.get_children():
			var c3 := child as Node3D
			if c3 == null:
				continue
			var ct := t * c3.transform
			var vi := c3 as MeshInstance3D
			if vi and vi.mesh:
				var a: AABB = ct * vi.mesh.get_aabb()
				box = a if first else box.merge(a)
				first = false
			stack.append([c3, ct])
	return box if not first else AABB(Vector3(-0.05, -0.2, -0.05), Vector3(0.1, 0.2, 0.1))


# --- Voxels (worker-safe: buffers only) -------------------------------------------------

## The part's shape layer by layer, as rasterised: per voxel layer y, [centre x, centre z, half
## width in x, half width in z] of its solid voxels (zeros for an empty layer). inner() measures
## depth against it.
static func profile(buffer: VoxelBuffer) -> PackedFloat32Array:
	var size := buffer.get_size()
	var out := PackedFloat32Array()
	out.resize(size.y * 4)
	for y in range(1, size.y - 1):
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for x in range(1, size.x - 1):
			for z in range(1, size.z - 1):
				if buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_COLOR) != VoxelArt.C.EMPTY:
					lo = Vector2(minf(lo.x, x), minf(lo.y, z))
					hi = Vector2(maxf(hi.x, x), maxf(hi.y, z))
		if lo.x == INF:
			continue
		out[y * 4] = (lo.x + hi.x) * 0.5
		out[y * 4 + 1] = (lo.y + hi.y) * 0.5
		out[y * 4 + 2] = maxf((hi.x - lo.x) * 0.5 + 0.5, 1.0)
		out[y * 4 + 3] = maxf((hi.y - lo.y) * 0.5 + 0.5, 1.0)
	return out


## How deep (x, y, z) sits in the part: 0 at its core, 1 at its outline (profile); -1 unknown.
static func depth_share(prof: PackedFloat32Array, x: int, y: int, z: int) -> float:
	var i := y * 4
	if i + 3 >= prof.size() or prof[i + 2] <= 0.0:
		return -1.0
	return Vector2((x - prof[i]) / prof[i + 2], (z - prof[i + 1]) / prof[i + 3]).length()


## What's inside the part at (x, y, z) once it's opened: -1 at the surface (skin and cloth, torn),
## then fat, flesh and bone at a limb's core; the skull just under a head's surface; ribs in the
## torso. Without `bone` (reduced gore) flesh where the bone would be.
static func inner(prof: PackedFloat32Array, x: int, y: int, z: int, kind: int, bone: bool) -> int:
	var rr := depth_share(prof, x, y, z)
	if rr < 0.0 or rr > SKIN_SHARE:
		return -1
	match kind:
		K_HEAD:
			if rr > SKULL_SHARE:
				return (VoxelArt.C.BONE if rr > SKULL_SHARE + 0.05 else VoxelArt.C.BONE_SHADE) if bone else VoxelArt.C.FLESH
			return VoxelArt.C.WOUND
		K_TORSO:
			if rr > FAT_SHARE:
				return VoxelArt.C.FAT
			if bone and rr > RIB_SHARE and posmod(y, RIB_EVERY) < RIB_THICK:
				return VoxelArt.C.BONE
			return VoxelArt.C.FLESH
	if rr > FAT_SHARE:
		return VoxelArt.C.FAT
	if rr < BONE_SHARE:
		return (VoxelArt.C.BONE if rr < BONE_SHARE * 0.7 else VoxelArt.C.BONE_SHADE) if bone else VoxelArt.C.FLESH
	return VoxelArt.C.FLESH


## A torn wall's colour at (x, y, z): its layer (inner), the flesh and skin right at the hole
## darker with blood (`deep`).
static func _wall(prof: PackedFloat32Array, x: int, y: int, z: int, kind: int, bone: bool, deep: bool) -> int:
	var c := inner(prof, x, y, z, kind, bone)
	if c == -1:
		return VoxelArt.C.WOUND_DARK if deep else VoxelArt.C.WOUND
	if c == VoxelArt.C.FLESH and deep:
		return VoxelArt.C.WOUND_DARK
	return c


## A ragged crater in `buffer` round `centre` (voxels) of about radius `r`: solid voxels inside
## go, those just outside it show what's under them (inner: torn skin, fat, flesh, bone; with no
## profile, torn flesh darker deeper in). Noise from `salt` jags the edge, so the same hole always
## carves the same way. Returns the voxels knocked out.
static func carve(buffer: VoxelBuffer, centre: Vector3, r: float, salt: int, prof := PackedFloat32Array(), kind := K_LIMB, bone := true, rim := RIM) -> int:
	var size := buffer.get_size()
	var reach := int(ceil(r * (1.0 + JAG) + rim))
	var c := Vector3i(roundi(centre.x), roundi(centre.y), roundi(centre.z))
	var removed := 0
	for x in range(maxi(c.x - reach, 1), mini(c.x + reach + 1, size.x - 1)):
		for y in range(maxi(c.y - reach, 1), mini(c.y + reach + 1, size.y - 1)):
			for z in range(maxi(c.z - reach, 1), mini(c.z + reach + 1, size.z - 1)):
				var v := buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_COLOR)
				if v == VoxelArt.C.EMPTY:
					continue
				var d := Vector3(x, y, z) - centre
				var dist := d.length()
				var edge := r * (1.0 + JAG * _jag(d, salt))
				if dist <= edge:
					buffer.set_voxel(VoxelArt.C.EMPTY, x, y, z, VoxelBuffer.CHANNEL_COLOR)
					removed += 1
				elif dist <= edge + rim:
					var deep := dist - edge < rim * 0.5
					var colour := (VoxelArt.C.WOUND_DARK if deep else VoxelArt.C.WOUND) if prof.is_empty() else _wall(prof, x, y, z, kind, bone, deep)
					buffer.set_voxel(colour, x, y, z, VoxelBuffer.CHANNEL_COLOR)
	return removed


## Fragment pocks: `count` small craters on the side of the part facing `dir` (raster space, toward
## the burst), placed by `salt`. Returns how many it made.
static func pepper(buffer: VoxelBuffer, dir: Vector3, count: int, salt: int, prof := PackedFloat32Array(), kind := K_LIMB, bone := true, spots: Array[Vector3i] = []) -> int:
	if spots.is_empty():
		spots = _facing(buffer, dir)
	if spots.is_empty():
		return 0
	var r := RandomNumberGenerator.new()
	r.seed = salt
	var made := 0
	for i in count:
		var p: Vector3i = spots[r.randi() % spots.size()]
		carve(buffer, Vector3(p) - dir * 0.5, r.randf_range(POCK_R.x, POCK_R.y), salt + i * 31, prof, kind, bone, POCK_RIM)
		made += 1
	return made


## Scorches the voxels facing `dir` (toward the burst): blackened in patches, more of them with
## `amount` (0..1), the same patches for the same `salt`. Returns how many.
static func scorch(buffer: VoxelBuffer, dir: Vector3, amount: float, salt: int, spots: Array[Vector3i] = []) -> int:
	var n := 0
	if spots.is_empty():
		spots = _facing(buffer, dir)
	for p: Vector3i in spots:
		var roll := float(absi((p.x * 73856093) ^ (p.y * 19349663) ^ (p.z * 83492791) ^ salt) % 1000) / 1000.0
		var patch := 0.5 + 0.5 * sin(p.x * 0.45 + float(salt % 97)) * cos(p.y * 0.38 + p.z * 0.41)
		if roll < amount * (0.55 + 0.6 * patch):
			buffer.set_voxel(VoxelArt.C.CHAR_DARK if roll < amount * 0.3 else VoxelArt.C.CHAR, p.x, p.y, p.z, VoxelBuffer.CHANNEL_COLOR)
			n += 1
	return n


static func _step(dir: Vector3) -> Vector3i:
	var step := Vector3i(roundi(dir.x * 1.4), roundi(dir.y * 1.4), roundi(dir.z * 1.4)).clamp(-Vector3i.ONE, Vector3i.ONE)
	return step if step != Vector3i.ZERO else Vector3i(0, 0, -1)


## Solid voxels with open air on their `dir` side: what a burst that way sees.
static func _facing(buffer: VoxelBuffer, dir: Vector3) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var size := buffer.get_size()
	var step := _step(dir)
	for x in range(1, size.x - 1):
		for y in range(1, size.y - 1):
			for z in range(1, size.z - 1):
				if buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_COLOR) == VoxelArt.C.EMPTY:
					continue
				var q := Vector3i(x, y, z) + step
				if q.x < 0 or q.y < 0 or q.z < 0 or q.x >= size.x or q.y >= size.y or q.z >= size.z \
						or buffer.get_voxel(q.x, q.y, q.z, VoxelBuffer.CHANNEL_COLOR) == VoxelArt.C.EMPTY:
					out.append(Vector3i(x, y, z))
	return out


## Cuts `buffer` through at layer `cut` (voxel y): the far side (below the cut for a limb, above
## it with `far_up`: the head) moves into a new buffer, returned; SEVER_SLAB layers each side of
## the cut are torn away, ragged; the faces left show what's inside (inner), and on a limb's stump
## the bone sticks out BONE_OUT layers past the flesh.
static func split(buffer: VoxelBuffer, cut: int, far_up := false, prof := PackedFloat32Array(), kind := K_LIMB, bone := true) -> VoxelBuffer:
	var size := buffer.get_size()
	var piece := VoxelBuffer.new()
	piece.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_8_BIT)
	piece.create(size.x, size.y, size.z)
	piece.fill(VoxelArt.C.EMPTY, VoxelBuffer.CHANNEL_COLOR)
	for x in range(1, size.x - 1):
		for z in range(1, size.z - 1):
			var ragged := int(round(sin(x * 1.7 + z * 0.9) + cos(z * 2.3 - x * 0.4)))  # -2..2 layers
			for y in range(1, size.y - 1):
				var v := buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_COLOR)
				if v == VoxelArt.C.EMPTY:
					continue
				var off := (y - cut) * (-1 if far_up else 1)  # > 0: the body's side; < 0: the far side
				var layer := inner(prof, x, y, z, kind, bone) if not prof.is_empty() else -1
				if absi(off - ragged) <= SEVER_SLAB:
					var stub := bone and kind == K_LIMB and off >= -BONE_OUT + SEVER_SLAB and (layer == VoxelArt.C.BONE or layer == VoxelArt.C.BONE_SHADE)
					buffer.set_voxel(layer if stub else VoxelArt.C.EMPTY, x, y, z, VoxelBuffer.CHANNEL_COLOR)
				elif off < ragged:
					buffer.set_voxel(VoxelArt.C.EMPTY, x, y, z, VoxelBuffer.CHANNEL_COLOR)
					var face := off - ragged >= -SEVER_SLAB - 2
					piece.set_voxel((_wall(prof, x, y, z, kind, bone, off - ragged >= -SEVER_SLAB - 1) if not prof.is_empty() else VoxelArt.C.WOUND) if face else v, x, y, z, VoxelBuffer.CHANNEL_COLOR)
				elif off - ragged <= SEVER_SLAB + 2:
					var deep := off - ragged <= SEVER_SLAB + 1
					buffer.set_voxel(_wall(prof, x, y, z, kind, bone, deep) if not prof.is_empty() else (VoxelArt.C.WOUND_DARK if deep else VoxelArt.C.WOUND), x, y, z, VoxelBuffer.CHANNEL_COLOR)
	return piece


## Cuts a limb nearly through at layer `cut`: as split, but a strip of tissue DANGLE_BRIDGE of
## its width on one side (by `salt`) holds, and the bone is broken. Returns {"buffer": what hangs
## (below the cut, moved out of `buffer`), "hinge": where it hangs from (raster), "side": the
## strip's side (raster direction), "cut": the layer}, or {} for a part too thin to cut.
static func dangle_split(buffer: VoxelBuffer, cut: int, salt: int, prof := PackedFloat32Array(), kind := K_LIMB, bone := true) -> Dictionary:
	var size := buffer.get_size()
	if cut < 2 or cut > size.y - 3 or prof.is_empty() or prof[cut * 4 + 2] <= 0.0:
		return {}
	var sides := [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
	var side: Vector3 = sides[absi(salt) % sides.size()]
	var cx := prof[cut * 4]
	var cz := prof[cut * 4 + 1]
	var hx := prof[cut * 4 + 2]
	var hz := prof[cut * 4 + 3]
	var piece := VoxelBuffer.new()
	piece.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_8_BIT)
	piece.create(size.x, size.y, size.z)
	piece.fill(VoxelArt.C.EMPTY, VoxelBuffer.CHANNEL_COLOR)
	for x in range(1, size.x - 1):
		for z in range(1, size.z - 1):
			var across := ((x - cx) / hx) * side.x + ((z - cz) / hz) * side.z  # -1..1 toward the strip
			var strip := across > 1.0 - DANGLE_BRIDGE * 2.0
			var ragged := int(round(sin(x * 1.3 + z * 1.1) + cos(z * 1.9 - x * 0.7) * 0.5))
			for y in range(1, size.y - 1):
				var v := buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_COLOR)
				if v == VoxelArt.C.EMPTY:
					continue
				var off := y - cut - ragged
				if absi(off) <= SEVER_SLAB:
					if strip:
						buffer.set_voxel(VoxelArt.C.WOUND if absi(off) < SEVER_SLAB else VoxelArt.C.WOUND_DARK, x, y, z, VoxelBuffer.CHANNEL_COLOR)
					else:
						buffer.set_voxel(VoxelArt.C.EMPTY, x, y, z, VoxelBuffer.CHANNEL_COLOR)
					if off < 0 and strip:  # the strip goes with what hangs
						piece.set_voxel(buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_COLOR), x, y, z, VoxelBuffer.CHANNEL_COLOR)
						buffer.set_voxel(VoxelArt.C.EMPTY, x, y, z, VoxelBuffer.CHANNEL_COLOR)
				elif off < 0:
					buffer.set_voxel(VoxelArt.C.EMPTY, x, y, z, VoxelBuffer.CHANNEL_COLOR)
					var face := off >= -SEVER_SLAB - 2
					piece.set_voxel(_wall(prof, x, y, z, kind, bone, off >= -SEVER_SLAB - 1) if face else v, x, y, z, VoxelBuffer.CHANNEL_COLOR)
				elif off <= SEVER_SLAB + 2:
					buffer.set_voxel(_wall(prof, x, y, z, kind, bone, off <= SEVER_SLAB + 1), x, y, z, VoxelBuffer.CHANNEL_COLOR)
	var hinge := Vector3(cx + side.x * hx, cut, cz + side.z * hz)
	return {"buffer": piece, "hinge": hinge, "side": side, "cut": cut}


## Corners of `buffer`'s solid voxels, a few layers at a time (raster space): a convex hull of
## them fits the piece (_fit_collider). Empty if there's nothing.
static func hull_points(buffer: VoxelBuffer, band := 4) -> PackedVector3Array:
	var out := PackedVector3Array()
	var size := buffer.get_size()
	var y := 1
	while y < size.y - 1:
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for yy in range(y, mini(y + band, size.y - 1)):
			for x in range(1, size.x - 1):
				for z in range(1, size.z - 1):
					if buffer.get_voxel(x, yy, z, VoxelBuffer.CHANNEL_COLOR) != VoxelArt.C.EMPTY:
						lo = lo.min(Vector3(x, yy, z))
						hi = hi.max(Vector3(x + 1, yy + 1, z + 1))
		if lo.x != INF:
			for corner in 8:
				out.append(Vector3(hi.x if corner & 1 else lo.x, hi.y if corner & 2 else lo.y, hi.z if corner & 4 else lo.z))
		y += band
	return out


## The lowest layer (voxel y) with anything in it.
static func _lowest_solid(buffer: VoxelBuffer) -> int:
	var size := buffer.get_size()
	for y in range(1, size.y - 1):
		for x in range(1, size.x - 1):
			for z in range(1, size.z - 1):
				if buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_COLOR) != VoxelArt.C.EMPTY:
					return y
	return 1


## The highest layer with anything in it.
static func _highest_solid(buffer: VoxelBuffer) -> int:
	var size := buffer.get_size()
	for y in range(size.y - 2, 0, -1):
		for x in range(1, size.x - 1):
			for z in range(1, size.z - 1):
				if buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_COLOR) != VoxelArt.C.EMPTY:
					return y
	return size.y - 2


static func _middle(buffer: VoxelBuffer) -> float:
	return (_lowest_solid(buffer) + _highest_solid(buffer)) * 0.5


## A limb's cut kept inside it: a stump and a piece both at least a few layers long.
static func _clamp_cut(buffer: VoxelBuffer, cut: float) -> float:
	var lo := _lowest_solid(buffer) + SEVER_SLAB + 4
	var hi := _highest_solid(buffer) - SEVER_SLAB - 4
	return clampf(cut, lo, maxf(hi, lo))


## -1..1 by direction from the centre: a few lumps round the crater, seeded.
static func _jag(d: Vector3, salt: int) -> float:
	if d.length_squared() < 0.0001:
		return 0.0
	var u := d.normalized()
	var a := float(salt % 997) * 0.37
	var b := float((salt / 997) % 991) * 0.53
	return clampf(0.6 * sin(u.x * 3.1 + a) * cos(u.y * 2.7 + b) + 0.4 * sin(u.z * 4.3 + a * 1.7 + u.x * 2.0), -1.0, 1.0)


static func _mesh_of(pivot: Node3D) -> MeshInstance3D:
	if pivot == null or not is_instance_valid(pivot) or pivot.get_child_count() == 0:
		return null
	return pivot.get_child(0) as MeshInstance3D
