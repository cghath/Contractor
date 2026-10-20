class_name Reloads
extends RefCounted
## How each weapon family is reloaded (Captain, 2026-10-20: "reload anims also need work";
## references he named: Sicario's AR reloads, other AK and AR reloads, common media, and "make
## sure our L85 has a good reload"). Learned from real technique (AR tactical and empty drills,
## the AK's rock-in and mag-to-mag strip, the SA80's drills, belt-fed loading) and from films and
## games that show reloads well: one continuous motion, the weapon tipped to glance at the well
## as the new magazine goes in, a tug to check it's seated, the bolt worked on an empty reload,
## and the weapon coming back up with a little overshoot.
##
## A reload is TACTICAL with rounds still in the magazine (one in the chamber: the old magazine
## is pulled and stowed) or EMPTY (it falls free and the bolt is worked at the end: the AR's bolt
## catch slapped, the AK's handle racked from underneath, the L85's bolt release pressed and its
## handle tapped forward, a belt-fed charged before the cover opens). An empty reload takes
## EMPTY_EXTRA_S longer, unless the weapon's stats name its own "reload_empty_s".
##
## PlayerInput plays KEYS in first person over the reload's length. Each key:
## [share of the reload, hand anchor, hand offset (m, view-model space), weapon offset (m:
## across toward the middle of the view, up, back), weapon turn (rad: muzzle up, turned in,
## rolled in), old magazine, new magazine, held magazine's tip (rad, nose up)]. Anchors are
## points on the weapon (VoxelArt.reload_points): &"rest" (the support hand's place on the
## handguard), &"mag" (the magazine's side, where the hand takes it), &"well" (the top of an
## internal magazine), &"pouch" (low by the belt, out of view), &"catch" (a bolt catch or release
## button), &"bolt" (a cocking or charging handle, a bolt handle) and &"cover" (a belt-fed's feed
## cover). The old magazine is &"in" (in the weapon), &"hand" (carried), &"drop" (falling free
## from that key on) or &"out" (gone); the new one &"out", &"hand" or &"in". Between keys the
## hand and the weapon ease (smoothstep); the magazines' states step at each key.

const AR := &"ar"
const AK := &"ak"
const BULLPUP := &"bullpup"
const BELT := &"belt"
const BOLT := &"bolt"            # an internal magazine, loaded through the top (a Mosin's clips)
const BOLT_MAG := &"bolt_mag"    # a bolt-action with a detachable magazine
const PISTOL := &"pistol"

## Seconds an empty reload adds (the bolt worked at the end), per family.
const EMPTY_EXTRA_S := {AR: 0.3, AK: 0.5, BULLPUP: 0.5, BELT: 0.5, BOLT: 0.0, BOLT_MAG: 0.4, PISTOL: 0.2}

const V0 := Vector3.ZERO
## The weapon's place while its magazine is changed, per family: tipped in so the well comes
## toward the eye, muzzle a little down, pulled in toward the chest. The L85 comes forward and
## down out of the shoulder instead, so its magazine behind the grip shows; a belt-fed drops to
## the hip with its feed tray turned up.
const POSE := {
	AR: [Vector3(0.06, 0.05, 0.06), Vector3(-0.15, 0.12, 0.55)],
	AK: [Vector3(0.05, 0.03, 0.08), Vector3(-0.08, 0.1, 0.7)],
	BULLPUP: [Vector3(0.03, -0.03, -0.06), Vector3(-0.25, 0.1, 0.4)],
	BELT: [Vector3(0.03, -0.04, 0.03), Vector3(-0.12, 0.08, 0.25)],
	BOLT: [Vector3(0.03, 0.03, 0.05), Vector3(-0.1, 0.08, 0.3)],
	PISTOL: [Vector3(0.04, 0.04, 0.08), Vector3(0.08, 0.15, 0.25)],
}
## The look: as the new magazine goes in, the weapon tips and rises a little more (this added).
const LOOK := [Vector3(0.0, 0.02, 0.01), Vector3(0.06, 0.03, 0.08)]
## Seating it bumps the weapon up; the tug dips it; a bolt slamming home jolts it forward and
## flicks the muzzle; coming back up it overshoots a touch (OVERSHOOT, a share of the pose).
const BUMP := Vector3(0.0, 0.015, 0.0)
const TUG := Vector3(0.0, -0.01, 0.0)
const SLAM := [Vector3(0.0, 0.0, -0.014), Vector3(0.04, 0.0, 0.0)]
const OVERSHOOT := 0.25
const DOWN := Vector3(0.0, -0.07, 0.01)  # the new magazine lined up under the well


## The family that reloads `item` (an ItemData weapon), from its model style.
static func family(item: ItemData) -> StringName:
	if item == null:
		return AR
	if item.slot == &"sidearm":
		return PISTOL
	match String(item.stats.get("model_style", "")):
		"ak": return AK
		"bullpup": return BULLPUP
		"pk", "m240", "m249": return BELT
		"mosin": return BOLT
		"chassis_bolt": return BOLT_MAG
	return AR


## Seconds to reload `item` (before wounds), empty or not.
static func seconds(item: ItemData, empty: bool) -> float:
	var base := float(item.stats.get("reload_s", 2.0))
	if not empty:
		return base
	return float(item.stats.get("reload_empty_s", base + float(EMPTY_EXTRA_S.get(family(item), 0.3))))


## The keys for `fam`, an empty reload or not (see the top of the file).
static func keys(fam: StringName, empty: bool) -> Array:
	var pose: Array = POSE.get(fam if POSE.has(fam) else (BOLT if fam == BOLT_MAG else AR))
	var p: Vector3 = pose[0]
	var r: Vector3 = pose[1]
	var look_p: Vector3 = p + LOOK[0]
	var look_r: Vector3 = r + LOOK[1]
	var over_p: Vector3 = p * OVERSHOOT * 0.2
	var over_r: Vector3 = Vector3(0.012, r.y * OVERSHOOT, r.z * OVERSHOOT)
	var slam_p: Vector3 = p + SLAM[0]
	var slam_r: Vector3 = r + SLAM[1]
	var lift := Vector3(0.0, 0.08, 0.0)
	match fam:
		AK:
			if empty:
				# Straight to the pouch; the new magazine's spine strips the old one out; rock it
				# in, tug; roll the rifle over and rack the handle from underneath.
				var rack_r := Vector3(r.x, r.y, -0.35)
				return [
					[0.0, &"rest", V0, V0, V0, &"in", &"out", 0.0],
					[0.1, &"rest", Vector3(-0.03, -0.12, 0.05), p, r, &"in", &"out", 0.0],
					[0.25, &"pouch", V0, p, r, &"in", &"hand", 0.0],
					[0.34, &"mag", Vector3(0.0, -0.04, -0.02), p, r, &"in", &"hand", 0.2],
					[0.4, &"mag", Vector3(0.0, -0.06, -0.06), p, r, &"drop", &"hand", 0.2],
					[0.48, &"mag", Vector3(0.0, -0.03, -0.03), look_p, look_r, &"out", &"hand", 0.35],
					[0.54, &"mag", V0, look_p + BUMP, look_r, &"out", &"in", 0.0],
					[0.58, &"mag", Vector3(0.0, -0.02, 0.0), p + TUG, r, &"out", &"in", 0.0],
					[0.66, &"bolt", Vector3(0.0, -0.04, 0.0), p, rack_r, &"out", &"in", 0.0],
					[0.71, &"bolt", V0, p, rack_r, &"out", &"in", 0.0],
					[0.76, &"bolt", Vector3(0.0, 0.0, 0.1), p, rack_r, &"out", &"in", 0.0],
					[0.79, &"bolt", Vector3(0.0, 0.0, 0.1), slam_p, rack_r + SLAM[1], &"out", &"in", 0.0],
					[0.9, &"rest", V0, over_p, over_r, &"out", &"in", 0.0],
					[1.0, &"rest", V0, V0, V0, &"out", &"in", 0.0],
				]
			# Thumb on the paddle, rock it forward and out, stow it; hook the new one's front lug
			# and rock it back to the click, tug.
			return [
				[0.0, &"rest", V0, V0, V0, &"in", &"out", 0.0],
				[0.12, &"mag", V0, p, r, &"in", &"out", 0.0],
				[0.18, &"mag", Vector3(0.0, -0.02, -0.03), p, r, &"hand", &"out", -0.35],
				[0.26, &"mag", Vector3(0.0, -0.12, -0.03), p, r, &"hand", &"out", -0.2],
				[0.42, &"pouch", V0, p, r, &"out", &"out", 0.0],
				[0.54, &"pouch", lift, p, r, &"out", &"hand", 0.0],
				[0.62, &"mag", Vector3(0.0, -0.03, -0.03), look_p, look_r, &"out", &"hand", 0.35],
				[0.68, &"mag", V0, look_p + BUMP, look_r, &"out", &"in", 0.0],
				[0.73, &"mag", Vector3(0.0, -0.02, 0.0), p + TUG, r, &"out", &"in", 0.0],
				[0.88, &"rest", V0, over_p, over_r, &"out", &"in", 0.0],
				[1.0, &"rest", V0, V0, V0, &"out", &"in", 0.0],
			]
		BULLPUP:
			if empty:
				# The empty falls from behind the grip; new one in, tug; the bolt release pressed
				# down, then over the top to tap the cocking handle forward (the British habit).
				return [
					[0.0, &"rest", V0, V0, V0, &"in", &"out", 0.0],
					[0.1, &"rest", Vector3(-0.03, -0.12, 0.08), p, r, &"drop", &"out", 0.0],
					[0.32, &"pouch", V0, p, r, &"out", &"out", 0.0],
					[0.42, &"pouch", lift, p, r, &"out", &"hand", 0.0],
					[0.52, &"mag", DOWN, look_p, look_r, &"out", &"hand", 0.0],
					[0.58, &"mag", V0, look_p + BUMP, look_r, &"out", &"in", 0.0],
					[0.62, &"mag", Vector3(0.0, -0.02, 0.0), p + TUG, r, &"out", &"in", 0.0],
					[0.67, &"catch", Vector3(0.0, 0.02, 0.0), p, r, &"out", &"in", 0.0],
					[0.71, &"catch", Vector3(0.0, -0.01, 0.0), slam_p, slam_r, &"out", &"in", 0.0],
					[0.79, &"bolt", Vector3(0.0, 0.03, 0.0), p, r, &"out", &"in", 0.0],
					[0.83, &"bolt", Vector3(0.0, 0.0, -0.025), p, r, &"out", &"in", 0.0],
					[0.92, &"rest", V0, over_p, over_r, &"out", &"in", 0.0],
					[1.0, &"rest", V0, V0, V0, &"out", &"in", 0.0],
				]
			# Out of the shoulder, the hand back under the cheek to the magazine behind the grip.
			return [
				[0.0, &"rest", V0, V0, V0, &"in", &"out", 0.0],
				[0.15, &"mag", V0, p, r, &"in", &"out", 0.0],
				[0.25, &"mag", Vector3(0.0, -0.12, 0.02), p, r, &"hand", &"out", 0.0],
				[0.42, &"pouch", V0, p, r, &"out", &"out", 0.0],
				[0.55, &"pouch", lift, p, r, &"out", &"hand", 0.0],
				[0.66, &"mag", DOWN, look_p, look_r, &"out", &"hand", 0.0],
				[0.72, &"mag", V0, look_p + BUMP, look_r, &"out", &"in", 0.0],
				[0.77, &"mag", Vector3(0.0, -0.02, 0.0), p + TUG, r, &"out", &"in", 0.0],
				[0.9, &"rest", V0, over_p, over_r, &"out", &"in", 0.0],
				[1.0, &"rest", V0, V0, V0, &"out", &"in", 0.0],
			]
		BELT:
			# Down to the hip; charge it (empty only); the cover up; box off, a new box on; the
			# belt laid on the tray; the cover slammed shut.
			var out: Array = [[0.0, &"rest", V0, V0, V0, &"in", &"out", 0.0]]
			if empty:
				out.append_array([
					[0.08, &"bolt", V0, p, r, &"in", &"out", 0.0],
					[0.14, &"bolt", Vector3(0.0, 0.0, 0.12), p, r, &"in", &"out", 0.0],
					[0.18, &"bolt", V0, slam_p, r, &"in", &"out", 0.0],
				])
			out.append_array([
				[0.24, &"cover", V0, p, r, &"in", &"out", 0.0],
				[0.3, &"cover", Vector3(0.0, 0.09, 0.03), p, r, &"in", &"out", 0.0],
				[0.38, &"mag", V0, p, r, &"in", &"out", 0.0],
				[0.46, &"mag", Vector3(0.0, -0.1, 0.05), p, r, &"hand", &"out", 0.0],
				[0.54, &"pouch", V0, p, r, &"out", &"out", 0.0],
				[0.62, &"pouch", lift, p, r, &"out", &"hand", 0.0],
				[0.7, &"mag", V0, look_p, look_r, &"out", &"in", 0.0],
				[0.76, &"cover", Vector3(0.0, 0.02, -0.02), p, r, &"out", &"in", 0.0],
				[0.82, &"cover", Vector3(0.0, 0.09, 0.03), p, r, &"out", &"in", 0.0],
				[0.86, &"cover", V0, p + Vector3(0.0, -0.02, 0.0), r, &"out", &"in", 0.0],
				[0.94, &"rest", V0, over_p, over_r, &"out", &"in", 0.0],
				[1.0, &"rest", V0, V0, V0, &"out", &"in", 0.0],
			])
			return out
		BOLT:
			# Bolt up and back, a clip of rounds pressed down through the top, bolt home.
			return [
				[0.0, &"rest", V0, V0, V0, &"in", &"out", 0.0],
				[0.1, &"bolt", V0, p, r, &"in", &"out", 0.0],
				[0.16, &"bolt", Vector3(0.0, 0.03, 0.0), p, r, &"in", &"out", 0.0],
				[0.22, &"bolt", Vector3(0.0, 0.03, 0.08), p, r, &"in", &"out", 0.0],
				[0.34, &"pouch", V0, p, r, &"in", &"out", 0.0],
				[0.44, &"pouch", lift, p, r, &"in", &"out", 0.0],
				[0.54, &"well", Vector3(0.0, 0.05, 0.0), look_p, look_r, &"in", &"out", 0.0],
				[0.62, &"well", V0, look_p + TUG, look_r, &"in", &"out", 0.0],
				[0.7, &"well", Vector3(0.0, 0.05, 0.0), p, r, &"in", &"out", 0.0],
				[0.78, &"bolt", Vector3(0.0, 0.03, 0.08), p, r, &"in", &"out", 0.0],
				[0.84, &"bolt", Vector3(0.0, 0.03, 0.0), p, r, &"in", &"out", 0.0],
				[0.88, &"bolt", V0, slam_p, r, &"in", &"out", 0.0],
				[0.95, &"rest", V0, over_p, over_r, &"in", &"out", 0.0],
				[1.0, &"rest", V0, V0, V0, &"in", &"out", 0.0],
			]
	# AR (and the bolt-action with a detachable magazine, and the pistol's shape).
	if empty:
		var work: Array
		if fam == BOLT_MAG:  # bolt up, back, forward, down
			work = [
				[0.66, &"bolt", Vector3(0.0, 0.03, 0.0), p, r, &"out", &"in", 0.0],
				[0.72, &"bolt", Vector3(0.0, 0.03, 0.08), p, r, &"out", &"in", 0.0],
				[0.78, &"bolt", Vector3(0.0, 0.03, 0.0), p, r, &"out", &"in", 0.0],
				[0.81, &"bolt", V0, slam_p, slam_r, &"out", &"in", 0.0],
			]
		elif fam == PISTOL:  # overhand on the slide, pulled back and let go
			work = [
				[0.7, &"bolt", Vector3(0.0, 0.02, 0.0), p, r, &"out", &"in", 0.0],
				[0.77, &"bolt", Vector3(0.0, 0.0, 0.05), p, r, &"out", &"in", 0.0],
				[0.8, &"bolt", Vector3(0.0, 0.0, 0.05), slam_p, slam_r, &"out", &"in", 0.0],
			]
		else:  # the support palm slaps the bolt catch: the bolt slams home
			work = [
				[0.68, &"catch", Vector3(0.0, 0.02, 0.0), p, r, &"out", &"in", 0.0],
				[0.72, &"catch", Vector3(0.0, -0.01, 0.0), slam_p, slam_r, &"out", &"in", 0.0],
			]
		return [
			[0.0, &"rest", V0, V0, V0, &"in", &"out", 0.0],
			[0.06, &"rest", Vector3(-0.03, -0.1, 0.05), p, r, &"drop", &"out", 0.0],
			[0.3, &"pouch", V0, p, r, &"out", &"out", 0.0],
			[0.4, &"pouch", lift, p, r, &"out", &"hand", 0.0],
			[0.5, &"mag", DOWN, look_p, look_r, &"out", &"hand", 0.0],
			[0.56, &"mag", V0, look_p + BUMP, look_r, &"out", &"in", 0.0],
			[0.6, &"mag", Vector3(0.0, -0.02, 0.0), p + TUG, r, &"out", &"in", 0.0],
		] + work + [
			[0.88, &"rest", V0, over_p, over_r, &"out", &"in", 0.0],
			[1.0, &"rest", V0, V0, V0, &"out", &"in", 0.0],
		]
	# Tactical: the old magazine stripped and stowed, the new one in with a look, seated, tugged.
	return [
		[0.0, &"rest", V0, V0, V0, &"in", &"out", 0.0],
		[0.12, &"mag", V0, p, r, &"in", &"out", 0.0],
		[0.2, &"mag", Vector3(0.0, -0.12, -0.02), p, r, &"hand", &"out", 0.0],
		[0.38, &"pouch", V0, p, r, &"out", &"out", 0.0],
		[0.5, &"pouch", lift, p, r, &"out", &"hand", 0.0],
		[0.6, &"mag", DOWN, look_p, look_r, &"out", &"hand", 0.0],
		[0.66, &"mag", V0, look_p + BUMP, look_r, &"out", &"in", 0.0],
		[0.71, &"mag", Vector3(0.0, -0.02, 0.0), p + TUG, r, &"out", &"in", 0.0],
		[0.86, &"rest", V0, over_p, over_r, &"out", &"in", 0.0],
		[1.0, &"rest", V0, V0, V0, &"out", &"in", 0.0],
	]


## The pose at share `u` of a reload with keys `ks`: {"anchor_a", "anchor_b", "w" (0..1 from a
## to b, eased), "hand_a", "hand_b", "pos", "rot", "old", "new", "tip", "since" (the share the
## current key began at)}.
static func sample(ks: Array, u: float) -> Dictionary:
	var i := 0
	while i < ks.size() - 2 and u >= float(ks[i + 1][0]):
		i += 1
	var a: Array = ks[i]
	var b: Array = ks[mini(i + 1, ks.size() - 1)]
	var span := maxf(float(b[0]) - float(a[0]), 0.0001)
	var w := smoothstep(0.0, 1.0, clampf((u - float(a[0])) / span, 0.0, 1.0))
	var held := u >= float(b[0])  # past the last key
	return {
		"anchor_a": a[1], "anchor_b": b[1], "w": 1.0 if held else w,
		"hand_a": a[2], "hand_b": b[2],
		"pos": (a[3] as Vector3).lerp(b[3], 1.0 if held else w),
		"rot": (a[4] as Vector3).lerp(b[4], 1.0 if held else w),
		"old": b[5] if held else a[5], "new": b[6] if held else a[6],
		"tip": lerpf(float(a[7]), float(b[7]), 1.0 if held else w),
		"since": float(b[0]) if held else float(a[0]),
	}
