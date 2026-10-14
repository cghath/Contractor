class_name MovementRules
extends RefCounted
## The numbers behind how a body moves under load, which way it moves, and how tired arms and
## lungs hold a weapon (movement phase 1, Captain 2026-10-14: the feel of Escape from Tarkov and
## of beta decay). Every tuning number for these rules is here, each with where it came from.
## SoldierMovement, Soldier and PlayerInput read them; AI bodies get the same rules through
## SoldierMovement.step (the turn cap is for players only: the AI has its own aim model).
##
## Contractor learns from those games; it is not a copy of either. Reference numbers below are
## Escape from Tarkov's, read from BSG's globals.json as served by SPT for game 0.16.9
## ("Tarkov:" in the comments). Tarkov cut its inertia by up to 70% in 2025 after players
## complained, so for a co-op squad game these lean to the lighter end: Contractor's soldier
## carries a fighting load (about 22-26 kg: rifle, plates, helmet, six magazines, water and
## meds) without penalty, and only loot and heavy gear on top of that slow him down.

enum Tier { LIGHT, BURDENED, OVERLOADED, CRITICAL }

# --- Load tiers ---------------------------------------------------------------------------

## Carried kg (Inventory.total_mass) where each tier starts. Tarkov: overweight from 26 kg, the
## worst at 77 kg (sprint gone by 72, walk speed falling from 35 to 80). Contractor: no cost to
## 25 kg (a full fighting load), BURDENED to 40 (slower, sprint shorter and dearer), OVERLOADED
## to 55 (no sprint), CRITICAL past it (no jump either), slowest at MAX_LOAD_KG.
const BURDENED_KG := 25.0
const OVERLOADED_KG := 40.0
const CRITICAL_KG := 55.0
const MAX_LOAD_KG := 70.0
## Speed multiplier at the start of each tier and at MAX_LOAD_KG, linear between (so there is no
## step at a boundary): research note A4/A5 (1.0 / 0.9 / 0.75 / 0.55; 0.55 was the old
## Soldier.MIN_LOAD_MULT at 60 kg).
const LOAD_SPEED: Array[float] = [1.0, 0.9, 0.75, 0.55]
const MIN_LOAD_MULT := 0.55
## Sprint's extra speed over a jog, as a fraction, from BURDENED_KG (1) to OVERLOADED_KG. Tarkov
## loses 90% of its sprint over 26-72 kg; at the kg where Contractor stops sprinting (40, 14 kg
## in) Tarkov has lost about 27% of it, so 0.7 here.
const SPRINT_LEFT_AT_OVERLOADED := 0.7
## Legs-stamina drain while sprinting, and the cost of a jump, by tier (research A5: x1, x1.5,
## x2; tier 3 can't sprint or jump, kept for completeness).
const TIER_DRAIN: Array[float] = [1.0, 1.5, 2.0, 2.0]
## Falls (WoundModel.FALL_SAFE_M is 3 m): Tarkov's safe drop is 3 m, 1.75 m overweight. From
## OVERLOADED, a drop counts as if it were FALL_SAFE_M / this times as high.
const OVERLOADED_FALL_SAFE_M := 1.75

# --- Direction ----------------------------------------------------------------------------

## Top speed moving sideways and backwards, as a fraction of forward (research A4; Tarkov's
## backpedal factor is 0.6 light to 0.4 at full inertia load, leaned lighter here: 0.7 light to
## 0.6 at MAX_LOAD_KG). Diagonals blend.
const STRAFE_MULT := 0.85
const BACK_MULT := 0.7
const BACK_MULT_LOADED := 0.6
## Sprint only within this many degrees of straight ahead (Tarkov: no sprinting while strafing).
const SPRINT_ARC_DEG := 45.0
## Sprint builds from a jog to full sprint speed over this long (research A5).
const SPRINT_RAMP_S := 0.4

# --- Legs stamina (SoldierMovement.stamina, 0..1) -------------------------------------------

## Regeneration by stance (Tarkov: x1.25 crouched, x1.45 prone).
const REGEN_CROUCH_MULT := 1.25
const REGEN_PRONE_MULT := 1.45
## A jump's cost, as a share of the pool (Tarkov: 14 of 115), times TIER_DRAIN; you need that
## much left to jump.
const JUMP_STAMINA := 14.0 / 115.0

# --- Arm stamina (SoldierMovement.arm_stamina, 0..1) -----------------------------------------

## Holding a weapon up (aimed) drains the arms in proportion to its mass (with its optic): a
## REF_WEAPON_KG weapon held up for ARM_HOLD_S empties them. Tarkov: 80 points, 1.1 a second
## (73 s) aimed with a typical rifle; lighter here (about 45 s with an optic'd M4), so a squad
## overwatching a street isn't forever lowering. ARM_REGEN_S refills them from empty
## (Tarkov 80 / 2.1 a second = 38 s; 20 s here).
const REF_WEAPON_KG := 4.0
const ARM_HOLD_S := 45.0
const ARM_REGEN_S := 20.0
## Aiming drain by stance (Tarkov: x0.75 crouched, x0.15 prone). A rested weapon (C) is held
## up by the rest: prone's x0.15 too (Contractor's choice).
const ARM_CROUCH_MULT := 0.75
const ARM_PRONE_MULT := 0.15
const ARM_MOUNTED_MULT := 0.15
## Arms empty, aiming drains the legs instead (Tarkov), at the arm rate x this (legs pool 115
## against arms 80 in Tarkov: the same points are a smaller share).
const ARMS_EMPTY_LEG_SHARE := 80.0 / 115.0
## Holding the breath costs the arms this much more while it lasts.
const BREATH_HOLD_ARM_MULT := 2.0

# --- ADS time (PlayerInput._update_aim) -------------------------------------------------------

## Seconds to bring a weapon up to the eye, by its mass with optic (Inventory.total_mass counts
## the optic the same way: Optics.extra_mass). Tarkov: 0.35 s at 0.6 kg to 0.95 s at 9 kg (its
## floors before ergonomics). Leaned lighter (x about 0.75): 0.25 s to 0.75 s, so an optic'd M4
## (3.9 kg) is about 0.45 s and a pistol 0.26 s. Empty arms make it ADS_TIRED_MULT x slower.
const ADS_LIGHT_KG := 0.6
const ADS_HEAVY_KG := 9.0
const ADS_LIGHT_S := 0.25
const ADS_HEAVY_S := 0.75
const ADS_TIRED_MULT := 0.5
## The eased blend reaches 95% in ads_seconds (exp(-3) = 0.05).
const ADS_EASE_K := 3.0

# --- Breathing sway and holding the breath (Soldier.aim_sway) ----------------------------------

## A breathing rise and fall of the aim, degrees at its widest: rested, then up to
## (1 + BREATH_ARMS_GAIN) x with empty arms and (1 + BREATH_LEGS_GAIN) x out of breath, at
## BREATH_HZ rested to BREATH_HZ_WINDED out of breath (research A5: breathing sway scaled by arm
## and legs deficit; rates are a resting and a hard-breathing human).
const BREATH_SWAY_DEG := 0.05
const BREATH_ARMS_GAIN := 2.0
const BREATH_LEGS_GAIN := 1.5
const BREATH_HZ := 0.25
const BREATH_HZ_WINDED := 0.7
## Hold breath (its own rebindable key, Shift by default while aiming: Shift is sprint, and
## there is no sprint while aiming): sway x BREATH_HOLD_SWAY for up to BREATH_HOLD_S, longer with
## fresh legs, then BREATH_RECOVER_S of gasping at x BREATH_GASP_SWAY with no hold (research A5).
const BREATH_HOLD_SWAY := 0.25
const BREATH_HOLD_S := 6.0
const BREATH_HOLD_MIN_S := 3.0
const BREATH_RECOVER_S := 2.0
const BREATH_GASP_SWAY := 1.8

# --- Turning (players only: PlayerInput) ------------------------------------------------------

## Most the view turns a second by tier (degrees): a light soldier flicks freely, a loaded one
## swings round slower. Mouse movement over the cap isn't lost: it plays out at the cap. Small
## aiming movements are well under every cap. (Research A4 proposed 900/600/360; lighter here.)
const MAX_YAW_RATE: Array[float] = [INF, 1080.0, 720.0, 450.0]
## Sprinting, mouse sensitivity falls to this under a full load (Tarkov: to 50%).
const SPRINT_TURN_LOADED := 0.5

# --- Weapon close to a wall (PlayerInput) -----------------------------------------------------

## The view model pulls back and down when a wall is closer ahead than this (metres from the eye)
## and is fully pulled at WALL_PULL_MIN_M.
const WALL_PULL_REACH_M := 0.85
const WALL_PULL_MIN_M := 0.3
const WALL_PULL_BACK := Vector3(0.02, -0.07, 0.2)

# --- Animation (CharacterModel) -------------------------------------------------------------------

## Breathing in the body's own animation: faster and deeper as the legs tire, up to these.
const ANIM_BREATH_RATE_WINDED := 2.5
const ANIM_BREATH_DEPTH_WINDED := 3.0


## The tier for `kg` carried.
static func tier_of(kg: float) -> int:
	if kg >= CRITICAL_KG:
		return Tier.CRITICAL
	if kg >= OVERLOADED_KG:
		return Tier.OVERLOADED
	if kg >= BURDENED_KG:
		return Tier.BURDENED
	return Tier.LIGHT


## Speed multiplier for `kg` carried: 1 to BURDENED_KG, then LOAD_SPEED between the tier starts.
static func load_speed_mult(kg: float) -> float:
	var points: Array[float] = [BURDENED_KG, OVERLOADED_KG, CRITICAL_KG, MAX_LOAD_KG]
	if kg <= points[0]:
		return LOAD_SPEED[0]
	for i in range(1, points.size()):
		if kg <= points[i]:
			var to := LOAD_SPEED[i] if i < LOAD_SPEED.size() else MIN_LOAD_MULT
			return lerpf(LOAD_SPEED[i - 1], to, (kg - points[i - 1]) / (points[i] - points[i - 1]))
	return MIN_LOAD_MULT


## 0 (BURDENED_KG or less) to 1 (MAX_LOAD_KG): how much of the load range is used.
static func load_fraction(kg: float) -> float:
	return clampf((kg - BURDENED_KG) / (MAX_LOAD_KG - BURDENED_KG), 0.0, 1.0)


static func can_sprint_at(tier: int) -> bool:
	return tier < Tier.OVERLOADED


static func can_jump_at(tier: int) -> bool:
	return tier < Tier.CRITICAL


## Sprint's share of its extra speed over a jog left at `kg`.
static func sprint_left(kg: float) -> float:
	return lerpf(1.0, SPRINT_LEFT_AT_OVERLOADED, clampf((kg - BURDENED_KG) / (OVERLOADED_KG - BURDENED_KG), 0.0, 1.0))


## Top-speed multiplier for moving along `input` (Input.get_vector: y < 0 is forward), heavier
## loads backpedalling slower: forward 1, sideways STRAFE_MULT, backwards BACK_MULT.
static func direction_mult(input: Vector2, kg := 0.0) -> float:
	if input.length_squared() < 0.0001:
		return 1.0
	var forward := -input.normalized().y
	var back := lerpf(BACK_MULT, BACK_MULT_LOADED, load_fraction(kg))
	return lerpf(STRAFE_MULT, 1.0, forward) if forward >= 0.0 else lerpf(STRAFE_MULT, back, -forward)


## Whether `input` is close enough to straight ahead to sprint along.
static func sprint_direction_ok(input: Vector2) -> bool:
	if input.length_squared() < 0.0001:
		return false
	return -input.normalized().y >= cos(deg_to_rad(SPRINT_ARC_DEG)) - 0.001  # W+A / W+D still sprint


## Mass of `weapon` as held, with the optic its `state` has on (Optics.extra_mass).
static func weapon_mass(weapon: ItemData, state := {}) -> float:
	if weapon == null:
		return 0.0
	return weapon.mass_kg + Optics.extra_mass(weapon, state)


## Seconds to aim a weapon of `kg`, with `arms` stamina (0..1) left.
static func ads_seconds(kg: float, arms := 1.0) -> float:
	var t := clampf((kg - ADS_LIGHT_KG) / (ADS_HEAVY_KG - ADS_LIGHT_KG), 0.0, 1.0)
	return lerpf(ADS_LIGHT_S, ADS_HEAVY_S, t) * (1.0 + ADS_TIRED_MULT * (1.0 - clampf(arms, 0.0, 1.0)))


## Arm stamina used per second holding a weapon of `kg` aimed (before the stance multiplier).
static func arm_drain(kg: float) -> float:
	return kg / REF_WEAPON_KG / ARM_HOLD_S


## The turn (radians) allowed this step towards `pending` at `rate` degrees a second.
static func capped_turn(pending: float, rate_deg: float, delta: float) -> float:
	if is_inf(rate_deg):
		return pending
	var most := deg_to_rad(rate_deg) * delta
	return clampf(pending, -most, most)
