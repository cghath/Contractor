class_name Traps
extends RefCounted
## Traps and defences that work on the dead (docs/survival_seasons.md; call 53, survival_building.md
## §9): built pieces (BuildPieces) checked by the host every TICK_S (Sieges runs it):
## - a spike pit kills one of the dead that walks into it (and wears: PIT_WEAR hp a kill);
## - wire (the field defences' piece) holds walkers tangled for WIRE_HOLD_S, and they chew through
##   it in time (WIRE_CHEW hp a second a head held);
## - a bear trap snaps on the first thing in it (the dead, or a careless man: a leg wound stub),
##   holds it BEAR_HOLD_S and must be reset ("Reset the trap");
## - an electric fence with power (Infrastructure) stuns the dead touching it for STUN_S;
## - a drawbridge is a door laid flat (Builder's doors), kill corridor markers count in the
##   defence value (Settlement.DEFENCE_PIECE).
## Held, stunned or frozen (Seasons) dead don't move or bite: holds(), read by ZombieAI.
## Every number here is Proposed.

const TICK_S := 0.25
const REACH_M := 0.35  # how far past a piece's box a body counts as in it
const PIT_WEAR := 15.0
const WIRE_HOLD_S := 8.0
const WIRE_CHEW := 1.5
const BEAR_HOLD_S := 20.0
const BEAR_WOUND := 0.5
const STUN_S := 4.0
const TRAP_KINDS: Array[String] = ["spike_pit", "wire", "bear_trap", "electric_fence"]


## Whether one of the dead is stopped now: frozen solid, held (wire, a bear trap) or stunned.
static func holds(body: Node) -> bool:
	if body == null:
		return false
	if body.has_meta(&"frozen"):
		return true
	var now := Soldier._now()
	return float(body.get_meta(&"held_until", -1.0)) > now or float(body.get_meta(&"stunned_until", -1.0)) > now


## Host: every trap in the zone against the dead in it. Returns what happened [[kind, body name], ...].
static func server_tick(level: Node) -> Array:
	var out: Array = []
	var b := Builder.find(level)
	if b == null:
		return out
	var dead := Survival.zombies(level)
	if dead.is_empty():
		return out
	var now := Soldier._now()
	for id: int in b.pieces.keys():
		if not b.pieces.has(id):
			continue
		var rec: Dictionary = b.pieces[id]
		var kind := String(rec.k)
		if not kind in TRAP_KINDS or not b.is_piece_built(id):
			continue
		if kind == "electric_fence" and not Infrastructure.is_powered(id):
			continue
		if kind == "bear_trap" and bool(rec.get("sprung", false)):
			continue
		var box := _box(rec)
		for z: Soldier in dead:
			if not is_instance_valid(z) or not z.vitals.is_up() or not box.has_point(z.global_position + Vector3.UP * 0.3):
				continue
			match kind:
				"spike_pit":
					z.vitals.server_kill()
					b.server_hit_piece(id, PIT_WEAR)
					out.append([kind, String(z.name)])
				"wire":
					z.set_meta(&"held_until", now + WIRE_HOLD_S)
					b.server_hit_piece(id, WIRE_CHEW * TICK_S)
					out.append([kind, String(z.name)])
				"bear_trap":
					z.set_meta(&"held_until", now + BEAR_HOLD_S)
					rec["sprung"] = true
					b._set_piece(id, rec)
					out.append([kind, String(z.name)])
					break
				"electric_fence":
					z.set_meta(&"stunned_until", now + STUN_S)
					out.append([kind, String(z.name)])
			if not b.pieces.has(id):
				break  # (worn through)
	return out


## Host: a bear trap reset ("" or why not).
static func server_reset(b: Builder, id: int) -> String:
	var rec: Dictionary = b.pieces.get(id, {})
	if rec.is_empty() or String(rec.k) != "bear_trap":
		return "?"
	if not bool(rec.get("sprung", false)):
		return "It's set"
	rec["sprung"] = false
	b._set_piece(id, rec)
	return ""


## A piece's world box, grown by REACH_M.
static func _box(rec: Dictionary) -> AABB:
	var c := Vector3i(int(rec.c[0]), int(rec.c[1]), int(rec.c[2]))
	var size := Vector3(BuildPieces.piece_size(String(rec.k), int(rec.r))) * BuildPieces.BLOCK_M
	return AABB(Vector3(c) * BuildPieces.BLOCK_M, size).grow(REACH_M)
