class_name SquadAI
extends Node
## Host-only brain for an AI Soldier. It drives the body only through the body's intent
## fields and the same host-validated requests a player sends (fire, reload, treat), so AI
## follows the same rules for ammo, reload time and treatment time.
##
## Every THINK_S each intent scores itself 0..1 and the best one wins, with hysteresis so
## close scores don't flip back and forth. Fighting is one intent with fire-team tactics
## inside it:
## - Take cover that blocks the threat, crouch when not shooting, stand up to fire bursts.
## - Rounds landing close suppress; a pinned soldier stays down and doesn't shoot.
## - Battle buddies never move at the same time: while one bounds to new cover, the other
##   holds and puts covering fire on the last known threat (bounding overwatch).
## - A frag goes to an enemy who stays hidden behind cover.
## Command menu orders shape this: movement orders, hold fire, Target (focus fire on one
## enemy) and Combat mode (Squad.CombatMode):
## - Safe: walk with the weapon lowered and don't start a fight; return fire once the squad
##   is fired upon.
## - Aware: upright and alert; fight from cover on contact.
## - Combat (default): as Aware, and crouch whenever halted.
## - Stealth: always crouched, never sprint; open fire only when fired upon or an enemy is
##   very close.
## Squadmates call out what they do (Callouts): contact, reloading, grenades, bounding.
##
## Casualty care on the wound model (design doc "Downed friendlies", "Medics" and "Fits the
## squad decisions"; Captain's playtest: medics put the wounded first, even in a firefight),
## for both sides and for players like anyone else. It uses only the treatment interface:
## Vitals.care_needed(), wound_list(), is_unconscious(), and the host request
## Soldier._server_treat (one item on one body part). There is no revive: a casualty wakes on
## their own when the wound model says so, and care keeps them alive and with the squad until then.
## - Who answers: the casualty's fire-team medic, otherwise their battle buddy, otherwise
##   the other medic (when the team's medic is down, busy or far), otherwise the nearest free
##   squadmate (responder_for), using what's in their IFAK. They say "Moving to Charlie",
##   then "Treating Charlie". Casualty care outscores fighting: the responder goes at once.
## - Under fire: smoke between a casualty in the open and the threat, drag them out of the
##   line of fire to cover, and treat massive bleeding (a tourniquet) while either of you is
##   still exposed. In cover, even mid-firefight, the rest follows in the care order: massive
##   bleeding, airway (NPA), chest seal, bandages and gauze, splint, then morphine for a
##   conscious casualty in pain (plan_care), re-checking care_needed() between items.
## - A responder pinned down while the casualty lies in the open can't reach them alive yet:
##   it smokes and puts suppressive fire on the threat first. Otherwise it fights only an
##   enemy within MEDIC_DEFEND_M, and the rest of the squad covers it with fire on the threat.
## - Afterwards it stays with an unconscious casualty and protects them (Care.GUARD), or out
##   of contact carries them after the squad leader (dragging them to cover if contact comes)
##   until they wake on their own. Anyone who lacks an item asks for a medic ("Need a medic
##   on Charlie"); a free medic with what's missing takes over (medic_for).
## - Self-care: a conscious wounded unit tourniquets its own arterial bleed at once, even
##   under fire, and does the rest (bandages, seals, splints, morphine) out of contact or in
##   cover. What it can't fix itself, it calls "Medic!" for. A medic doesn't use on itself
##   an item nobody else on its side carries (massive bleeding aside).
## - Dead friendlies (players' bodies too) stay where they fell; out of contact a squadmate
##   (their buddy first) carries the body after the squad leader.
## - Unconscious foes are ignored, except for a dead-check while clearing or assaulting
##   through a position (DEAD_CHECK_M).
## - Scavenging (Scavenge): out of contact a unit short of ammunition, medical items, grenades
##   or armor goes through a nearby dead body and takes what it needs, one item at a time,
##   enemies and fallen AI squadmates alike (never a dead player's body: that gear waits for
##   its player). One unit per body (Soldier.scavenged_by). Friendlies only while following,
##   and within SCAVENGE_LEASH_M of the squad leader; the command menu orders one to a body
##   or forbids it (scavenge_allowed).

enum Intent { FOLLOW, HOLD, MOVE_TO, PATROL, INVESTIGATE, FIGHT, CASUALTY, RELOAD, HEAL, SCAVENGE, ESCORT, FALL_BACK, TACTIC }
## Casualty care: NONE, the living-casualty steps (REACH to GUARD and CARRY), or carrying a
## dead friendly's BODY.
enum Care { NONE, REACH, DRAG, TREAT, GUARD, CARRY, BODY }

const THINK_S := 0.5
## Tactics (queue 17 core; Squad, SquadTactics). A unit has the squad evaluator's task for it
## (set_task) and may have a command-menu tactic order (give_tactic), which wins over the task.
## Kinds: "base" and "suppress" put rounds on "aim" while nothing is in sight, "watch" faces
## "point" (these three leave the unit doing what it was: fighting from cover, following,
## holding); the rest move it (Intent.TACTIC): "maneuver" along "route" then fights there,
## "assault" onto "point", "clear" (its "slot" in "op", SquadTactics.clear_op), "garrison"
## ("spot", "face", "port"), "cover" (the best cover near it), "break" (back to "point", smoke
## over open ground), "bound" (to "point" by bounding overwatch), "search" (to "point", looking),
## "give_ammo" (to "who", hands over magazines), "pick_pack" (back for the pack it dropped). An ordered one that ends (cover, break, bound,
## clear, give_ammo) leaves the unit holding where it got to; a timed one ("until") just ends.
const MOVING_TACTICS: Array[StringName] = [&"maneuver", &"assault", &"clear", &"garrison", &"cover", &"break", &"bound", &"search", &"give_ammo", &"pick_pack"]
## How long "Suppress" lasts (Squad.order_suppress).
const SUPPRESS_ORDER_S := 20.0
## An evaluator task that moves the unit scores above fighting where it stands and below falling
## back broken; an ordered tactic above that, below casualty care and an empty magazine.
const TACTIC_SCORE := 0.75
const ORDERED_SCORE := 0.85
## Suppressive rounds wander this far round the point (a position, not a pixel), a new spot each burst.
const SUPPRESS_SPREAD_M := 1.5
## Bounding overwatch: legs of at most BOUND_LEG_M, cover to cover (within BOUND_COVER_M of the
## leg's end); the one who just got there covers BOUND_COVER_S before it may go again.
const BOUND_LEG_M := 10.0
const BOUND_COVER_M := 3.0
const BOUND_COVER_S := 1.0
## Breaking contact over more than SMOKE_OPEN_M, in contact within SCREEN_RANGE_M of the threat,
## a unit throws smoke between (SMOKE_OUT_M out) unless the squad screened within SCREEN_M in
## the last SCREEN_S (_screened).
const SMOKE_OPEN_M := 8.0
const SCREEN_RANGE_M := 120.0
const SMOKE_OUT_M := 7.0
const SCREEN_S := 20.0
const SCREEN_M := 15.0
## "Give me ammo": this many magazines of the asker's ammunition, handed over within GIVE_M.
const GIVE_MAGS := 2
const GIVE_M := 2.0
## "Heal up": self-care first for this long, even in contact.
const HEAL_ORDER_S := 30.0
## "Stance" orders (Squad.command "stance:<name>"): what want_stance the unit keeps (auto: -1).
const STANCE_ORDERS := {"up": SoldierMovement.Stance.STAND_HIGH, "crouch": SoldierMovement.Stance.CROUCH_MID,
	"prone": SoldierMovement.Stance.PRONE, "auto": -1}
const SCAN_S := 0.3
const CONTACT_MEMORY_S := 8.0
const INVESTIGATE_MEMORY_S := 25.0
## A partly-spotted enemy (Spotting.SUSPECT) is looked for this long after last glimpsed.
const SUSPECT_S := 8.0
## Morale (queue 17 part 4; proposed): 0..1, heading for a level set by discipline, less for
## each friend down nearby (MORALE_NEAR_M), the unit's own injury, suppression and being
## outnumbered (enemies spotted against friends up nearby), more with the squad leader close.
## It falls fast and comes back slowly. Under MORALE_SHAKEN aim suffers; under MORALE_BROKEN in
## contact a hostile falls back (a friendly too, but only on Follow: orders win) and, seen
## and alone, may give up (PeopleLayer.surrender_reason).
const MORALE_NEAR_M := 40.0
const MORALE_PER_DOWN := 0.12
const MORALE_INJURY := 0.4
const MORALE_SUPPRESSION := 0.3
const MORALE_OUTNUMBERED := 0.1
const MORALE_LEADER := 0.1
const MORALE_LEADER_M := 15.0
const MORALE_FALL_PER_S := 0.15
const MORALE_RISE_PER_S := 0.03
const MORALE_SHAKEN := 0.4
const MORALE_BROKEN := 0.25
const MORALE_SHAKEN_AIM_DEG := 3.0
## Falling back: this far from the threat (or toward the leader), into cover within FALL_BACK_COVER_M.
const FALL_BACK_M := 20.0
const FALL_BACK_COVER_M := 8.0
const SIGHT_RANGE := 60.0
const SUPPRESSED := 0.5
const PINNED := 0.85
const HYSTERESIS := 0.1
const ARRIVE := 0.7
const RUN_DISTANCE := 5.0
const WAYPOINT_REACH := 0.45
const REPATH_S := 1.0
const COVER_RINGS: Array[float] = [2.0, 4.0, 6.0, 8.0, 10.0]
const COVER_SEARCH_S := 1.0
## Cover that only hides you (wood or sheet metal a rifle round goes through, see
## VoxelWorld.MATERIALS) scores this much worse than cover that stops a round arriving with
## SOFT_COVER_TEST_J (an M855 at close range), so AI picks concrete when it has the choice.
const SOFT_COVER_PENALTY := 6.0
const SOFT_COVER_TEST_J := 1650.0
const ADVANCE_AFTER_S := 6.0
const ADVANCE_STEP := 8.0
const WORLD_MASK := 1
const TURN_RATE := 7.0
const GRENADE_COOLDOWN_S := 15.0
## One frag per spot per squad within this long, over this spread (proposed).
const SQUAD_FRAG_GAP_S := 6.0
const SQUAD_FRAG_SPREAD_M := 6.0
## Points checked along a frag's arc before throwing it (_lob_clear).
const LOB_CHECKS := 10
const CASUALTY_REACH := 1.6
## Proposed: a fire team's medic further than this from a casualty counts as far, so the
## buddy or the other medic answers instead.
const MEDIC_FAR_M := 40.0
## Proposed: under fire, smoke goes between a casualty in the open and the threat from this
## close to them.
const SMOKE_RANGE_M := 25.0
## The smoke a responder screens a casualty with (coloured smokes are kept for signalling).
const SCREEN_SMOKE := &"smoke_grenade"
## Under fire only massive bleeding is treated (a tourniquet); the rest waits for cover.
const UNDER_FIRE_KINDS: Array[String] = ["arterial"]
## Massive bleeding: a medic treats this on itself even with the squad's only item for it.
const MASSIVE_BLEED_KINDS: Array[String] = ["arterial", "junctional"]
## Proposed: a unit looking after a casualty fights back only at an enemy this close (or
## while guarding them); further off it leaves the fight to the squad.
const MEDIC_DEFEND_M := 10.0
## Proposed: squadmates in contact put covering fire on the threat while a squadmate this
## close is out reaching or dragging a casualty.
const COVER_MEDIC_M := 30.0
## Proposed: an unconscious casualty knocked out with blood to spare (under the wound model's
## UNCONSCIOUS_LOST) is watched where they lie until they wake, unless the squad leader is
## further than this from them; then they're carried after the squad like anyone who won't
## wake soon.
const STAY_WITH_M := 20.0
## Ordered to move while carrying a casualty: cover within LAY_DOWN_M of the order point to lay
## them down in; lying within LAY_NEAR_M of it counts as laid down there (proposed).
const LAY_DOWN_M := 8.0
const LAY_NEAR_M := 2.0
## The care order once safe, by care_needed() kind: massive bleeding, airway, tension (the needle), chest, the
## pelvic binder (a broken pelvis bleeds heavily inside), other bleeding, circulation (IV or IO, a bag, a pressure bag), restarting a heart
## (epinephrine, shocks, CPR), the heart rate, fractures, burns, pain, epinephrine's wake-up roll
## (internal bleeding sits with the other bleeding; a blanket goes on after the bags). Kinds not
## listed go just before pain.
const CARE_RANK: Array[String] = ["arterial", "airway", "tension", "chest", "junctional", "pelvis", "venous", "internal", "muscle", "graze",
	"access", "fluids", "pressure", "hypothermia", "epinephrine", "defib", "cpr", "racing", "slow_heart", "fracture", "burn", "pain", "wake"]
## Proposed: seconds past an item's time before checking whether it worked.
const TREAT_MARGIN_S := 0.4
## Proposed: tries at one task (same body, part and kind) that change nothing before giving up on it.
const TREAT_TRIES := 2
## Proposed: tries at a line ("access"): an IV in shock misses often, and each miss uses a
## catheter, so a medic keeps going while it carries more.
const ACCESS_TRIES := 4
## Restarting a heart (shocks, CPR cycles) goes on as long as the arrest window lasts.
const RESTART_KINDS: Array[String] = ["defib", "cpr"]
## Proposed: morphine only for a conscious casualty in at least this much pain.
const MORPHINE_PAIN := 0.5
## Proposed: a wounded unit calls "Medic!" at most this often, and counts as asking for that long.
const MEDIC_CALL_S := 20.0
## Proposed: how close a carer must be for a conscious casualty to stop and be treated.
const BEING_TREATED_M := 6.0
## Proposed: out of contact, squadmates recover friendly bodies within this range.
const BODY_RECOVER_M := 60.0
## Proposed: how much recovering a fallen friendly's body scores out of contact. Above
## following, holding and moving (0.5) plus HYSTERESIS, so a squadmate who is following
## switches to it; below fighting (0.7), a low-magazine reload (0.65) and casualty care.
const BODY_RECOVER_SCORE := 0.63
## HVT escort (Captain, 2026-10-11; Squad.order_escort): up to ESCORTS_MAX squadmates keep an
## HVT with the squad while it follows the player. The first escort leads him (he follows it
## to its formation spot); the other keeps ESCORT_GUARD_M from him, behind him; in contact
## both fight within ESCORT_LEASH_M of a spot between him and the threat. Escorting scores
## ESCORT_SCORE: above fighting (0.7), below casualty care, a dry-magazine reload and their
## own bleeding. They take no other casualty, body or loot meanwhile. Not godlike: if he bolts
## they react after ESCORT_REACT_S (unskilled .. skilled; slower when suppressed, not at all
## while pinned or blinded), and a grab within GRAB_M works with GRAB_CHANCE plus GRAB_SKILL
## times their combat skill, again every GRAB_RETRY_S. A wounded HVT is a medical priority:
## his escorts treat him with what they carry, and a free medic is pulled to him (distance
## times HVT_MEDIC_PULL) and takes over. Proposed numbers.
const ESCORTS_MAX := 2
const ESCORT_SCORE := 0.75
const ESCORT_GUARD_M := 1.8
## The escort leading him waits for him beyond this.
const ESCORT_WAIT_M := 4.0
const ESCORT_LEASH_M := 3.0
const ESCORT_REACT_S := Vector2(1.6, 0.6)
const ESCORT_SUPPRESSED_S := 1.0
const GRAB_M := 1.6
const GRAB_CHANCE := 0.55
const GRAB_SKILL := 0.25
const GRAB_RETRY_S := 1.5
const HVT_MEDIC_PULL := 0.25
## What makes a conscious HVT a casualty to see to: bleeding, airway and chest.
const HVT_CARE_KINDS: Array[String] = ["arterial", "junctional", "venous", "internal", "airway", "tension", "chest"]
## Proposed: scavenging (Scavenge). Bodies within SCAVENGE_RANGE_M of the unit, and for
## friendlies within SCAVENGE_LEASH_M of the squad leader, once SCAVENGE_CALM_S have passed
## since the last contact (armor swaps wait ARMOR_CALM_S). A body is worth going to when what
## it holds scores at least SCAVENGE_MIN (Scavenge.best_pick; about a third of a basic load
## of ammo short); once there, the unit keeps taking things down to SCAVENGE_KEEP. Its score
## runs from SCAVENGE_SCORE (above following plus HYSTERESIS) up by SCAVENGE_NEED_SCORE times
## the need; an ordered unit scores SCAVENGE_ORDER_SCORE. A body done with is left alone for
## SCAVENGE_SKIP_S.
const SCAVENGE_RANGE_M := 30.0
const SCAVENGE_LEASH_M := 40.0
const SCAVENGE_CALM_S := 10.0
const ARMOR_CALM_S := 30.0
const SCAVENGE_MIN := 0.25
const SCAVENGE_KEEP := 0.1
const SCAVENGE_SCORE := 0.61
const SCAVENGE_NEED_SCORE := 0.06
const SCAVENGE_ORDER_SCORE := 0.68
const SCAVENGE_SKIP_S := 60.0
## Proposed: a responder whose distance to the casualty hasn't closed by REACH_PROGRESS_M in
## REACH_STUCK_S (something the navmesh doesn't know about is in the way, such as a player)
## sidesteps DETOUR_M for DETOUR_S, alternating sides. After REACH_GIVE_UP_S without getting
## closer it hands the casualty on and leaves them to others for REACH_SKIP_S.
const REACH_PROGRESS_M := 0.5
const REACH_STUCK_S := 1.5
const DETOUR_M := 1.8
const DETOUR_S := 1.2
const REACH_GIVE_UP_S := 12.0
const REACH_SKIP_S := 20.0
## Proposed: while clearing or assaulting through a position, unconscious foes this close get
## dead-checked (shot); otherwise targeting skips them.
const DEAD_CHECK_M := 8.0
## Proposed: in Stealth, open fire unprovoked only at an enemy this close.
const STEALTH_ENGAGE_M := 15.0
## Proposed: in Safe, only run to catch up from this far behind.
const SAFE_CATCH_UP_M := 15.0
## Suppression or injury rising this much in one frame means this unit was fired upon.
const FIRED_ON_SUPPRESSION := 0.001
const FIRED_ON_INJURY := 0.02
## Proposed: don't shoot when a friendly is this close (metres) to the line of fire.
const FRIENDLY_CLEARANCE := 0.7
## Fire discipline (Captain, P0164 queue 17 part 5; proposed): rounds that miss fly on, so
## people up to DOWNRANGE_M past the aim point count as in the line too; the clearance grows
## with the cone this unit's rounds spread over (_fire_cone) the further down the line they
## are; someone lying (prone, or down) counts LYING_EXTRA_M wider around their chest (the
## length of them); someone beside or behind the muzzle (less than MUZZLE_M along the line)
## isn't in it.
const DOWNRANGE_M := 60.0
const LYING_EXTRA_M := 0.6
const MUZZLE_M := 0.5
## Grenade discipline (queue 17 part 5; proposed): nobody to protect within FRAG_RADIUS plus
## FRAG_SAFETY_M of where a frag lands (it bounces and rolls), nor within LOB_FRIEND_M of its
## arc (it would hit them and drop at their feet).
const FRAG_SAFETY_M := 2.0
const LOB_FRIEND_M := 1.0
## Proposed (Captain, 2026-10-12: the squad seemed a bit unintelligent): the friendly squad's
## senses and habits. A squadmate hears an enemy shot within HEAR_SHOT_M (a suppressed one
## within HEAR_SUPPRESSED_M) and takes contact toward the shooter, placed up to
## HEARD_ERROR_PER_100M metres off for every 100 m away; contact one squadmate sees reaches
## the others within SHARE_CONTACT_M (as if called out).
const HEAR_SHOT_M := 200.0
const HEAR_SUPPRESSED_M := 40.0
const HEARD_ERROR_PER_100M := 6.0
const SHARE_CONTACT_M := 80.0
## Contact passed on (queue 17 part 3): seconds by voice, by radio beyond SHARE_CONTACT_M
## (both need a radio; proposed).
const SHARE_VOICE_S := 1.0
const SHARE_RADIO_S := 2.5
const RADIO := &"radio"
## Friendlies see this far (hostiles SIGHT_RANGE) and stay in contact this long after the last
## sign of the enemy (hostiles CONTACT_MEMORY_S).
const SQUAD_SIGHT_RANGE := 120.0
const SQUAD_CONTACT_MEMORY_S := 20.0
## The lead still for LEAD_HALT_S (moved less than LEAD_MOVED_M): squadmates take a spot beside
## something solid within HALT_COVER_M of their slot, and watch outward.
const LEAD_HALT_S := 1.5
const LEAD_MOVED_M := 1.0
const HALT_COVER_M := 2.0
## Pinned in the open: a squadmate crawls (crouched) to cover within this far instead of freezing.
const PINNED_COVER_M := 6.0

## 0..1: aim error and reaction speed.
@export var combat := 0.6
## 0..1: how firmly orders are kept under fire.
@export var discipline := 0.6
## Hostiles: stay at the post instead of walking the patrol route.
@export var guard := false

var body: Soldier
var squad: Squad
## Battle buddy (lives on the body, so players have one too).
var buddy: Soldier:
	get:
		var s := get_parent() as Soldier
		return s.buddy if s else null
var intent := Intent.FOLLOW
var target: Soldier
## This unit's standing order (friendlies), set from the command menu.
var order := Squad.Order.FOLLOW
## Tactics: the squad evaluator's task for this unit, and a command-menu tactic order (wins).
## See MOVING_TACTICS. {} for none.
var task: Dictionary = {}
var ordered: Dictionary = {}
## A stance order (STANCE_ORDERS; -1: the unit's own choice) and a "Heal up" order's end.
var stance_order := -1
var _heal_until := -1000.0
var _suppress_jitter := Vector3.ZERO
## "Drop packs here": the pack this unit left on the ground ({"id", "pos"}), {} for none.
var dropped_pack: Dictionary = {}
## Command menu "Hold fire": don't shoot at all until told to open fire.
var hold_fire := false
## Command menu "Combat mode": how this unit moves, fires and holds stance.
var combat_mode := Squad.CombatMode.COMBAT
## Command menu "Target": the enemy to focus fire on while it can be seen (null: free choice).
var focus: Soldier
var care := Care.NONE
## Who this unit looks after (a living casualty, or a dead friendly's body for Care.BODY).
var casualty: Soldier
## Looking after a casualty and unable to do more: asks for a medic who has `wanted`.
var wants_medic := false
## Items this unit lacks for its casualty, or for itself when it calls "Medic!".
var wanted: Array[StringName] = []
## True while moving to new cover in contact (the buddy holds and covers meanwhile).
var bounding := false
## Command menu "Scavenge freely" / "Don't scavenge" (friendlies).
var scavenge_allowed := true
## Command menu "Scavenge that body": the body to go through now (null: none ordered).
var scavenge_order: Soldier
## The body this unit is going through (SCAVENGE).
var loot_body: Soldier
## The HVT this unit escorts (Squad.order_escort), or null; escort_order: lower leads him.
var escorting: Soldier
var escort_order := 0
## Host: grabs that held a bolting HVT (tests read it).
var grabs := 0
## Scales the grab chance (tests).
var grab_scale := 1.0
var _react_at := -1.0  # when this escort reacts to its HVT bolting (-1: he isn't)
var _grab_next := 0.0

var _path := PackedVector3Array()
var _path_index := 0
var _path_target := Vector3.INF
var _repath_cd := 0.0
var _destination := Vector3.ZERO
var _has_destination := false
var _run := false
var _cover_point := Vector3.ZERO
var _has_cover := false
var _hold_point := Vector3.ZERO
var _move_point := Vector3.ZERO
## Where a casualty carried under a move order is laid down (null until worked out).
var _lay_spot: Variant = null
var _lay_for := Vector3.INF  # the point _lay_spot was found for (a moving CCP: found again)
var _patrol_index := 0
var _think_cd := 0.0
var _scan_cd := 0.0
var _briefing_check_s := 0.0
var _briefing_was_open := false
var _cover_cd := 0.0
var _grenade_cd := GRENADE_COOLDOWN_S * 0.4
var _last_contact := -1000.0
## Spotting (Spotting): awareness of each enemy in sight, by instance id, 0..1; at 1 they're a
## target. The best partly-spotted one is suspected: looked at, and a hostile goes to search.
var _aware := {}
var _suspect_pos := Vector3.ZERO
var _suspect_at := -1000.0
var _preset := ""
var _scatter: ZoneScatter  # the zone's scrub and trees (Spotting.foliage_m): _zone_scatter
var _scatter_found := false
## Contact reports from squadmates on their way: enemy instance id -> {"point", "due", "who"}.
var _reports := {}
## Morale (MORALE_*), and where this unit is falling back to (null: not worked out).
var morale := 1.0
var _fall_back_point: Variant = null
var _morale_state := "steady"
var _no_los_s := 0.0
var _burst_left := 0
var _pause_until := 0.0
var _next_shot := 0.0
var _advance_anchor := Vector3.ZERO
var _advancing := false
var _smoke_used := false
var _candidate: Soldier  # a casualty this unit should answer (refreshed each think)
var _treat_until := -1.0  # an item in progress until then
var _treat_target: Soldier
var _treat_key := ""
var _treat_before := 0
var _failures := {}  # task key -> treatments that changed nothing
var _suppressing := false  # pinned while the casualty lies in the open: fire on the threat first
var _cover_medic := false  # a squadmate nearby is out reaching or dragging a casualty (refreshed each think)
var _asked_medic := false
var _answered := false
var _medic_called_at := -1000.0
var _reach_best := INF  # closest this unit got to its casualty on the way (Care.REACH)
var _reach_progress_at := 0.0  # when it last got REACH_PROGRESS_M closer
var _detour := Vector3.ZERO  # a sidestep around something in the way
var _detour_until := -1.0
var _detour_next := -1.0  # no new sidestep before then (try the direct way in between)
var _detour_side := 1.0
var _skip := {}  # casualty instance id -> Soldier._now() until which this unit leaves them to others
var _dead_check: Soldier  # an unconscious foe being dead-checked, kept until dead or out of range
var _score := 0.0
var _ready_done := false
var _was_bounding := false
var _fired_on_at := -1000.0
var _last_suppression := 0.0
var _last_injury := 0.0
var _loot_pick := {}  # the item being taken off loot_body until _loot_until
var _loot_until := -1.0
var _loot_score := 0.0  # what going through the chosen body scored
var _loot_candidate: Soldier  # the body worth going through (refreshed each think)
var _looted := {}  # body instance id -> Soldier._now() until which this unit leaves it alone
var _lead_last := Vector3.INF  # where the lead stood when last seen moving (_lead_halted)
var _lead_still_s := 0.0
var _halt_spot: Variant = null  # where this unit waits while the lead is halted (null: its slot)


static func of(s: Node) -> SquadAI:
	return s.get_node_or_null(^"SquadAI") as SquadAI if s else null


func _physics_process(delta: float) -> void:
	if not _ready_done:
		_setup()
		return
	if _briefing_open():
		_stop()  # nobody moves or fires while the squad reads the briefing
		target = null
		body.ai_status = "Waiting (briefing)"
		return
	var now := Soldier._now()
	if _treat_until >= 0.0 and now >= _treat_until:
		_finish_treatment()
	if not body.vitals.is_up():
		_stop()
		if care != Care.NONE:
			_end_care()
		if loot_body != null:
			_end_scavenge()  # let go of the body, so a bearer waiting on it isn't stuck
		body.ai_status = body.vitals.condition_text()
		return
	_grenade_cd -= delta
	_cover_cd -= delta
	_notice_fire(now)
	if body.threat_time > _last_contact:
		_last_contact = body.threat_time
	if not _reports.is_empty():
		_take_reports(now)
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_S
		var previous := target
		target = _find_target()
		if target != null and target != previous and target.vitals.is_up():
			_next_shot = maxf(_next_shot, now + lerpf(0.9, 0.25, combat))  # reaction time
			var callouts := Callouts.of(body)
			if callouts:
				callouts.contact(body, target)
			if body.faction == &"hostile":
				Alert.server_sighting(body, target.global_position)  # hot zones: he'll radio it in (4B part 3)
	if target != null and target.vitals.is_up():
		_last_contact = now
		body.threat_pos = target.global_position
		body.threat_time = now
		_no_los_s = 0.0
		if _scan_cd == SCAN_S:
			_share_contact(target.global_position, now)  # once a scan, not every frame
			if squad:
				squad.note_enemy(target, target.global_position)
	else:
		_no_los_s += delta  # a body being dead-checked is no contact
	_think_cd -= delta
	if _think_cd <= 0.0:
		_think_cd = THINK_S
		_update_morale(THINK_S)
		_choose_intent()
	_act()
	_steer(delta)
	_shoot()
	body.ai_status = status_text()


## Whether the level's briefing is open (players planning before the deployment starts).
## Looked up once a second.
func _briefing_open() -> bool:
	_briefing_check_s -= get_physics_process_delta_time()
	if _briefing_check_s <= 0.0:
		_briefing_check_s = 1.0
		var briefing := MapNodes.briefing(body)
		_briefing_was_open = briefing != null and briefing.is_open()
	return _briefing_was_open


func in_contact() -> bool:
	return Soldier._now() - _last_contact < _contact_memory()


func _friendly() -> bool:
	return body != null and body.faction == &"friendly"


func _contact_memory() -> float:
	return SQUAD_CONTACT_MEMORY_S if _friendly() else CONTACT_MEMORY_S


## Host: `shooter` fired from `origin`; squadmates of the friendly squad within earshot take
## contact toward it (a rough bearing: further off, further out), unless they had fresher
## contact of their own this last second.
static func server_heard_shot(shooter: Soldier, origin: Vector3, suppressed: bool) -> void:
	if shooter == null or not shooter.is_inside_tree():
		return
	var reach := HEAR_SUPPRESSED_M if suppressed else HEAR_SHOT_M
	var now := Soldier._now()
	for n in shooter.get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s == shooter or not s.is_ai() or s.faction == shooter.faction or not s.vitals.is_up() or SquadAI.of(s) == null:
			continue
		var d := s.global_position.distance_to(origin)
		if d > reach:
			continue
		var error := HEARD_ERROR_PER_100M * d / 100.0
		var heard_at := origin + Vector3(randf_range(-error, error), 0.0, randf_range(-error, error))
		# Hearing feeds spotting (queue 17 part 2): the shooter is half found already.
		SquadAI.of(s).hear(shooter, heard_at, Spotting.HEARD_SHOT)
		if s.faction != &"friendly" or now - s.threat_time < 1.0:
			continue  # the squad takes a heard shot as contact; hostiles go and search
		s.threat_pos = heard_at
		s.threat_time = now


## Heard `who` at about `where`: awareness of them rises by `amount` (never to a full spot:
## that takes sight), and they're suspected there.
func hear(who: Soldier, where: Vector3, amount: float) -> void:
	var id := who.get_instance_id()
	var a: float = _aware.get(id, 0.0)
	_aware[id] = maxf(a, minf(a + amount, Spotting.HEARD_MAX))
	_suspect_pos = where
	_suspect_at = Soldier._now()
	if squad and body and who.faction != body.faction:
		squad.note_enemy(who, where, true)


## Contact this unit sees reaches its squadmates (friendly squad; queue 17 part 3): by voice
## within SHARE_CONTACT_M after SHARE_VOICE_S, farther by radio after SHARE_RADIO_S when both
## carry one. It lands as where the enemy was when called (stale by then), and half finds him
## for them (Spotting.TOLD), so they spot him sooner.
func _share_contact(point: Vector3, now: float) -> void:
	if squad == null or not _friendly():
		return
	var radio := body.inventory.count_of(RADIO) > 0
	for s in squad.members():
		if s == body or not s.vitals.is_up():
			continue
		var d := s.global_position.distance_to(body.global_position)
		var delay := SHARE_VOICE_S if d <= SHARE_CONTACT_M else (SHARE_RADIO_S if radio and s.inventory.count_of(RADIO) > 0 else -1.0)
		if delay < 0.0:
			continue
		var ai := SquadAI.of(s)
		if ai == null:  # a player: they hear it, and have their own eyes
			if s.threat_time < now:
				s.threat_pos = point
				s.threat_time = now
			continue
		var id := target.get_instance_id() if target else 0
		if ai._reports.has(id):
			ai._reports[id].point = point  # still on its way: the latest position goes with it
		else:
			ai._reports[id] = {"point": point, "due": now + delay, "who": target}


## Reports from squadmates (_share_contact) that have arrived: contact, and half a spot.
func _take_reports(now: float) -> void:
	for id: int in _reports.keys():
		var r: Dictionary = _reports[id]
		if now < float(r.due):
			continue
		_reports.erase(id)
		if body.threat_time < now - SHARE_VOICE_S:
			body.threat_pos = r.point
			body.threat_time = now
		var who: Soldier = r.who as Soldier if is_instance_valid(r.who) else null
		if who and who.vitals.is_up():
			hear(who, r.point, Spotting.TOLD)


## In contact and willing to fight: Safe units leave a contact alone until fired upon.
func fighting() -> bool:
	return in_contact() and (combat_mode != Squad.CombatMode.SAFE or engaged())


## The enemy this unit fights right now: its target, except that a unit going to, moving or
## treating a casualty leaves anyone further than MEDIC_DEFEND_M to the squad (guarding them,
## it fights as usual), and an escort running down its bolting HVT leaves everyone. Null for none.
func _foe() -> Soldier:
	if target == null:
		return null
	if intent == Intent.ESCORT and _react_at >= 0.0 and Soldier._now() >= _react_at:
		return null  # running down a bolting HVT: weapon down, flat out
	if intent == Intent.CASUALTY and care in [Care.REACH, Care.DRAG, Care.TREAT, Care.CARRY] \
			and body.global_position.distance_to(target.global_position) > MEDIC_DEFEND_M:
		return null
	return target


## In contact, with a squadmate within COVER_MEDIC_M out reaching or dragging a casualty:
## this unit puts covering fire on the threat while it has no target of its own.
func _medic_needs_cover() -> bool:
	if not in_contact() or intent == Intent.CASUALTY:
		return false
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var other := SquadAI.of(n)
		if other and other != self and other.body != null and other.body.faction == body.faction and other.body.vitals.is_up() \
				and other.intent == Intent.CASUALTY and other.care in [Care.REACH, Care.DRAG] \
				and other.body.global_position.distance_to(body.global_position) <= COVER_MEDIC_M:
			return true
	return false


## This unit, or its squad, was fired upon recently.
func engaged() -> bool:
	return Soldier._now() - _fired_on_at < CONTACT_MEMORY_S or (squad != null and squad.is_engaged())


## Whether the orders and combat mode let this unit shoot at what it sees now.
func weapons_free() -> bool:
	if hold_fire:
		return false
	if StringName(_tactic().get("kind", &"")) == &"suppress":
		return true  # ordered to: whatever the combat mode
	match combat_mode:
		Squad.CombatMode.SAFE:
			return engaged()
		Squad.CombatMode.STEALTH:
			return engaged() or (target != null and body.global_position.distance_to(target.global_position) <= STEALTH_ENGAGE_M)
	return true


## An order from the command menu. `slot` and `count` spread a group of units around the
## point so they don't all head for the same spot.
func on_order(new_order: Squad.Order, point: Vector3, slot := 0, count := 1) -> void:
	order = new_order
	set_escort(null)  # a movement order takes them off the escort
	_hold_point = body.global_position
	var side := squad.leader.global_basis.x if squad and is_instance_valid(squad.leader) else body.global_basis.x
	_move_point = point + side * (slot - (count - 1) / 2.0) * 1.5
	ordered = {}  # a movement order replaces a tactic order
	_lay_spot = null
	_has_cover = false
	_think_cd = 0.0


## Command menu action: throw a grenade at a point. False if this unit can't.
func order_throw(id: StringName, point: Vector3) -> bool:
	if not body.vitals.is_up() or body.carrying != null:
		return false
	_aim_at(point)
	return _throw(id, point)


## Where it is heading (the destination it is walking to), or Vector3.INF if nowhere (debug overlay).
func destination() -> Vector3:
	return _destination if _has_destination else Vector3.INF


func status_text() -> String:
	var who := _name_of(casualty)
	match intent:
		Intent.CASUALTY:
			match care:
				Care.REACH:
					return "Covering %s" % who if _suppressing else "Going to %s" % who
				Care.DRAG:
					return "Dragging %s to cover" % who
				Care.TREAT:
					if _treat_until < 0.0 and is_instance_valid(casualty) and casualty.vitals.downed:
						return "Watching over %s" % who
					return "Treating %s" % who
				Care.GUARD:
					return "Guarding %s" % who
				Care.CARRY:
					return "Carrying %s" % who if body.carrying == casualty else "Watching over %s" % who
				Care.BODY:
					return "Carrying %s's body" % who if body.carrying == casualty else "Recovering %s's body" % who
		Intent.FIGHT:
			if body.stunned_s > 0.0:
				return "Blinded"
			if body.suppression >= PINNED:
				return "Pinned down"
			if bounding:
				return "Bounding"
			return "Engaging" if target else ("In cover" if _at_cover() else "In contact")
		Intent.RELOAD:
			return "Reloading"
		Intent.SCAVENGE:
			var dead := loot_body if loot_body else _loot_candidate
			var what := _name_of(dead) if dead and dead.faction == body.faction else "the body"
			return "Searching %s" % what if _loot_until >= 0.0 else "Going to %s" % what
		Intent.HEAL:
			if _treat_target == body and _treat_until >= 0.0:
				return "Treating self"
			return "Being treated" if _being_treated() else "Patching up"
		Intent.HOLD:
			return "Holding"
		Intent.ESCORT:
			return ("Going after %s" if _react_at >= 0.0 else "Escorting %s") % _name_of(escorting)
		Intent.MOVE_TO:
			return "Moving" if body.global_position.distance_to(_move_point) > ARRIVE + 0.5 else "In position"
		Intent.PATROL:
			return "Patrolling"
		Intent.INVESTIGATE:
			return "Searching"
		Intent.FALL_BACK:
			return "Falling back"
		Intent.TACTIC:
			return _tactic_text()
	return "Following"


# --- Setup ----------------------------------------------------------------

func _setup() -> void:
	body = get_parent() as Soldier
	if body == null or not body.is_node_ready():
		return
	_hold_point = body.global_position
	_move_point = body.global_position
	morale = _morale_base()
	_ready_done = true
	_pass_through_squadmates()


## AI on the same side moves through each other (host only, where AI moves): squadmates
## crowding a doorway or a casualty no longer wedge each other in. Players still bump into
## AI and AI into players.
func _pass_through_squadmates() -> void:
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var other := n as Soldier
		if other and other != body and other.is_ai() and other.faction == body.faction:
			body.add_collision_exception_with(other)
			other.add_collision_exception_with(body)


# --- Intent selection -----------------------------------------------------

func _choose_intent() -> void:
	var scores := {}
	var contact := in_contact()
	var weapon := body.active_weapon()
	var rounds := body.inventory.rounds_in(body.active_slot) if weapon else 0
	var full := _mag_size(weapon)
	var spare := body.inventory.spare_rounds(Soldier._ammo_of(weapon)) if weapon else 0

	if body.faction == &"friendly":
		match order:
			Squad.Order.FOLLOW:
				scores[Intent.FOLLOW] = 0.5
			Squad.Order.HOLD:
				scores[Intent.HOLD] = 0.5
			Squad.Order.MOVE:
				# Disciplined soldiers keep moving under fire a little longer.
				scores[Intent.MOVE_TO] = 0.5 + (0.25 * discipline if contact else 0.0)
		if escort_valid():
			scores[Intent.ESCORT] = ESCORT_SCORE
		elif escorting != null:
			set_escort(null)
	else:
		scores[Intent.PATROL] = 0.3
		if Soldier._now() - _last_contact < INVESTIGATE_MEMORY_S or suspecting():
			scores[Intent.INVESTIGATE] = 0.55
	# Casualty care, both sides: a living casualty comes before almost anything; a fallen
	# friendly's body is carried only out of contact.
	_candidate = _find_casualty() if care == Care.NONE or care == Care.BODY else null
	if (care != Care.NONE and care != Care.BODY) or _candidate != null:
		scores[Intent.CASUALTY] = 0.9
	elif not contact and (care == Care.BODY or _find_body() != null):
		scores[Intent.CASUALTY] = BODY_RECOVER_SCORE
	_maybe_call_medic()
	_cover_medic = _medic_needs_cover()
	if fighting():
		scores[Intent.FIGHT] = 0.7
	if broken() and in_contact() and (not _friendly() or order == Squad.Order.FOLLOW):
		scores[Intent.FALL_BACK] = 0.8  # above fighting, below casualty care and an empty magazine
	if weapon and rounds == 0 and spare > 0:
		scores[Intent.RELOAD] = 0.95
	elif weapon and rounds < full * 0.35 and spare > 0 and target == null:
		scores[Intent.RELOAD] = 0.65
	var heal := _self_care_score()
	if heal > 0.0:
		scores[Intent.HEAL] = heal
	var t := _tactic()
	if StringName(t.get("kind", &"")) in MOVING_TACTICS:
		scores[Intent.TACTIC] = ORDERED_SCORE if not ordered.is_empty() else TACTIC_SCORE
	var loot := _scavenge_score(contact)
	if loot > 0.0:
		scores[Intent.SCAVENGE] = loot

	var best: Intent = intent
	var best_score := -1.0
	for key: Intent in scores:
		if scores[key] > best_score:
			best = key
			best_score = scores[key]
	var current: float = scores.get(intent, -1.0)
	if best != intent and best_score < current + HYSTERESIS:
		return
	if best != intent:
		if intent == Intent.CASUALTY and care != Care.NONE and care != Care.BODY and best_score < 0.95:
			return  # don't abandon a casualty for anything short of an empty magazine or your own bleed
		intent = best
		_score = best_score
		if intent != Intent.CASUALTY and care == Care.BODY:
			_end_care()  # put the body down to fight
		if intent != Intent.SCAVENGE and loot_body != null:
			_end_scavenge()  # contact, a casualty, or something more pressing


# --- Acting ---------------------------------------------------------------

func _act() -> void:
	body.want_crouch = false
	_was_bounding = bounding
	bounding = false  # only _fight moves to cover
	_suppressing = false  # only _care_reach holds back to suppress
	body.want_aim = _foe() != null
	match intent:
		Intent.FOLLOW:
			if fighting():
				_halt_spot = null
				_fight(squad.leader.global_position if squad and is_instance_valid(squad.leader) else body.global_position, 8.0)
			else:
				var spot := _follow_spot()
				_go(spot)
				if _halt_spot != null and _flat_distance(spot) <= ARRIVE + 0.3:
					_face(body.global_position + _outward(spot))  # halted: watch out from the lead
		Intent.HOLD:
			if fighting():
				_fight(_hold_point, 4.0)
			else:
				_go(_hold_point, false)
		Intent.MOVE_TO:
			_go(_move_point, true)
			if body.global_position.distance_to(_move_point) <= ARRIVE + 0.5:
				_hold_point = _move_point
		Intent.PATROL:
			_patrol()
		Intent.INVESTIGATE:
			_go(_suspect_pos if suspecting() and _suspect_at > _last_contact else body.threat_pos, false)
		Intent.FIGHT:
			_fight_from_context()
		Intent.RELOAD:
			_do_reload()
		Intent.HEAL:
			_do_self_care()
		Intent.CASUALTY:
			_do_care()
		Intent.SCAVENGE:
			_do_scavenge()
		Intent.ESCORT:
			_do_escort()
		Intent.FALL_BACK:
			_do_fall_back()
		Intent.TACTIC:
			_do_tactic(_tactic())
	_apply_combat_mode()
	if stance_order >= 0:
		body.want_stance = stance_order if intent != Intent.CASUALTY else -1  # (casualty care kneels as it needs)


## Combat mode stance and weapon carry for the movement and fighting intents (reloading,
## healing and casualty care keep their own stance).
func _apply_combat_mode() -> void:
	if intent in [Intent.RELOAD, Intent.HEAL, Intent.CASUALTY, Intent.SCAVENGE]:
		return
	var fight := intent == Intent.FIGHT or fighting()
	match combat_mode:
		Squad.CombatMode.SAFE:
			if not fight:
				body.want_aim = false  # weapon lowered
				body.want_crouch = false
		Squad.CombatMode.COMBAT:
			if not fight and _halted():
				body.want_crouch = true
		Squad.CombatMode.STEALTH:
			body.want_crouch = true


## Standing still: no destination, or already there.
func _halted() -> bool:
	return not _has_destination or _flat_distance(_destination) <= ARRIVE + 0.3


## Notices incoming fire (suppression or a wound) and tells the squad.
func _notice_fire(now: float) -> void:
	var injury := body.vitals.injury()
	if body.suppression > _last_suppression + FIRED_ON_SUPPRESSION or injury > _last_injury + FIRED_ON_INJURY:
		_fired_on_at = now
		if squad:
			squad.note_fired_on()
	_last_suppression = body.suppression
	_last_injury = injury


func _fight_from_context() -> void:
	if body.faction != &"friendly":
		if target == null and _no_los_s > ADVANCE_AFTER_S and not _buddy_bounding() and not _advancing:
			# Push one bound toward where the enemy was last seen.
			_advancing = true
			_advance_anchor = body.global_position.move_toward(body.threat_pos, ADVANCE_STEP)
			_has_cover = false
			_no_los_s = 0.0
		if target != null and target.vitals.is_up():
			_advancing = false  # a dead-check doesn't end the push through the position
		_fight(_advance_anchor if _advancing else (_cover_point if _has_cover else body.global_position), 6.0)
		if _advancing and _at_cover():
			_advancing = false
		return
	match order:
		Squad.Order.HOLD:
			_fight(_hold_point, 4.0)
		Squad.Order.MOVE:
			_fight(_move_point, 5.0)
		_:
			_fight(squad.leader.global_position if squad and is_instance_valid(squad.leader) else body.global_position, 8.0)


## Fight from cover near `anchor`, within `leash` metres of it. Buddies take turns moving.
func _fight(anchor: Vector3, leash: float) -> void:
	# Pinned in the open, a squadmate crawls to the nearest cover rather than freezing there
	# (friendly squad; enemies still go to ground where they are).
	var crawl := _friendly() and body.suppression >= PINNED and body.stunned_s <= 0.0 and not _at_cover()
	if crawl:
		anchor = body.global_position
		leash = PINNED_COVER_M
	var cover_ok := _has_cover and _cover_point.distance_to(anchor) <= leash + 1.0 and _cover_protects(_cover_point)
	if not cover_ok and _cover_cd <= 0.0 and (crawl or (not _buddy_bounding() and body.suppression < PINNED)) and body.stunned_s <= 0.0:
		_cover_cd = COVER_SEARCH_S
		var spot: Variant = find_cover(anchor, leash)
		if spot != null:
			_cover_point = spot
			_has_cover = true
	if crawl and _has_cover:
		_go(_cover_point, false)  # crouched (want_crouch below), never sprinting
	elif _has_cover and body.suppression < PINNED and body.stunned_s <= 0.0 and (_was_bounding or not _buddy_bounding()):
		_go(_cover_point, true)  # hold and cover while the buddy bounds, unless already moving
	elif _friendly() and not _has_cover and not crawl and body.stunned_s <= 0.0 and body.suppression < PINNED and _flat_distance(anchor) > leash:
		# No cover found: don't stand in the open far from the lead (or the post); get back in.
		var back := Vector3(body.global_position.x - anchor.x, 0.0, body.global_position.z - anchor.z).normalized()
		_go(anchor + back * leash * 0.5, true)
	else:
		_has_destination = false
	bounding = _has_destination and not _at_cover()
	if bounding and not _was_bounding and in_contact():
		_call_bound()
	# Keep your head down unless you're shooting.
	var shooting := target != null and Soldier._now() >= _pause_until
	body.want_crouch = body.suppression >= PINNED or body.stunned_s > 0.0 or (_at_cover() and not shooting)


## Following out of contact: the formation slot; with the lead halted (friendly squad, not in
## Safe), a spot beside something solid near the slot, found once per halt.
func _follow_spot() -> Vector3:
	var slot := squad.follow_point(body) if squad else body.global_position
	if not _friendly() or combat_mode == Squad.CombatMode.SAFE or not _lead_halted():
		_halt_spot = null
		return slot
	if _halt_spot == null:
		var found: Variant = _find_halt_spot(slot)
		_halt_spot = found if found != null else slot  # nothing solid near: wait at the slot
	return _halt_spot


## Whether the lead has stood still (within LEAD_MOVED_M) for LEAD_HALT_S. Call once a frame.
func _lead_halted() -> bool:
	if squad == null or not is_instance_valid(squad.leader):
		return false
	var at := squad.leader.global_position
	if _lead_last == Vector3.INF or at.distance_to(_lead_last) > LEAD_MOVED_M:
		_lead_last = at
		_lead_still_s = 0.0
		return false
	_lead_still_s += get_physics_process_delta_time()
	return _lead_still_s >= LEAD_HALT_S


## Flat direction from the lead out through `point` (where a halted squadmate watches).
func _outward(point: Vector3) -> Vector3:
	var lead := squad.leader.global_position if squad and is_instance_valid(squad.leader) else body.global_position
	var out := Vector3(point.x - lead.x, 0.0, point.z - lead.z)
	if out.length() < 0.3:
		out = -body.global_basis.z
		out.y = 0.0
	return out.normalized()


## Near `slot` (within HALT_COVER_M, on the navmesh, not someone else's spot): best with
## something solid in front of it facing out from the lead, else something beside it. Null if
## there's nothing solid near.
func _find_halt_spot(slot: Vector3) -> Variant:
	var map := body.get_world_3d().navigation_map
	var world := body.get_world_3d()
	var out := _outward(slot)
	var candidates: Array[Vector3] = [slot]
	for ring in [HALT_COVER_M * 0.6, HALT_COVER_M]:
		for k in 8:
			var angle := TAU * k / 8.0
			candidates.append(slot + Vector3(cos(angle), 0.0, sin(angle)) * ring)
	var best: Variant = null
	var best_score := INF
	for p in candidates:
		var q := NavigationServer3D.map_get_closest_point(map, p)
		if Vector2(q.x - p.x, q.z - p.z).length() > 0.6 or _halt_spot_taken(q):
			continue
		var eye := q + Vector3.UP * 0.9
		var score := INF
		if not Throwables.clear_line(world, eye, eye + out * 1.5):
			score = 0.0  # something to crouch behind, facing out
		else:
			for side in [out.cross(Vector3.UP), -out.cross(Vector3.UP), -out]:
				if not Throwables.clear_line(world, eye, eye + (side as Vector3) * 0.8):
					score = 2.0  # against a wall at least
					break
		if score == INF:
			continue
		score += Vector2(q.x - slot.x, q.z - slot.z).length()
		if score < best_score:
			best = q
			best_score = score
	return best


func _halt_spot_taken(point: Vector3) -> bool:
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var other := SquadAI.of(n)
		if other and other != self and other._halt_spot != null and (other._halt_spot as Vector3).distance_to(point) < 1.2:
			return true
	return false


func _patrol() -> void:
	if guard or squad == null or squad.patrol.is_empty():
		_go(_hold_point, false)
		return
	var point := squad.patrol[_patrol_index % squad.patrol.size()]
	_go(point, false)
	if _flat_distance(point) <= ARRIVE + 0.3:
		_patrol_index += 1


func _do_reload() -> void:
	if in_contact() and _has_cover and not _at_cover():
		_go(_cover_point, true)
		return
	_has_destination = false
	body.want_crouch = in_contact()
	var weapon := body.active_weapon()
	if weapon == null or Soldier._now() < body._busy_until:
		return
	if body.inventory.rounds_in(body.active_slot) >= _mag_size(weapon):
		_think_cd = 0.0
		return
	body._busy_until = Soldier._now() + body.reload_seconds(weapon)
	body.is_reloading = true
	body._server_reload.rpc_id(1, body.active_slot)
	_think_cd = body.reload_seconds(weapon)
	_callout(&"reloading")


# --- Casualty care --------------------------------------------------------

## Whether `s` needs someone else's help: unconscious (downed, players too), or conscious
## and calling for a medic. The dead are bodies, not casualties.
static func needs_help(s: Soldier) -> bool:
	if s == null or not is_instance_valid(s) or s.is_queued_for_deletion() or s.vitals.is_dead():
		return false
	if s.vitals.downed:
		return true
	if Person.is_hvt(s):
		return s.vitals.care_needed().any(func(t: Dictionary) -> bool: return String(t.kind) in HVT_CARE_KINDS)
	var ai := SquadAI.of(s)
	return ai != null and ai.asking_for_medic()


## This unit called "Medic!" within the last MEDIC_CALL_S and still needs care.
func asking_for_medic() -> bool:
	return Soldier._now() - _medic_called_at < MEDIC_CALL_S and body != null and body.vitals.is_up() \
		and not body.vitals.care_needed().is_empty()


## The casualty-care order applied to Vitals.care_needed() tasks (Dictionaries with "part",
## "kind" and "item"): under fire only massive bleeding (a tourniquet); once safe, massive
## bleeding, airway, chest, the other bleeding, fractures, then pain (CARE_RANK). Morphine is
## only for a conscious casualty. Tasks of the same rank keep their order.
static func plan_care(tasks: Array[Dictionary], under_fire: bool, conscious: bool) -> Array[Dictionary]:
	var ranked: Array = []
	for i in tasks.size():
		var kind := String(tasks[i].kind)
		if under_fire and kind not in UNDER_FIRE_KINDS:
			continue
		if kind == "pain" and not conscious:
			continue
		var rank := CARE_RANK.find(kind)
		if rank < 0:
			rank = CARE_RANK.size() - 1  # unknown kinds: just before pain
			ranked.append([rank * 2, i])
		else:
			ranked.append([rank * 2 + (1 if kind == "pain" else 0), i])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array[Dictionary] = []
	for r: Array in ranked:
		out.append(tasks[r[1]])
	return out


## Who answers casualty `c` (design doc "Medics"): the medic of c's fire team when free and
## not far (MEDIC_FAR_M), otherwise c's battle buddy, otherwise another free medic,
## otherwise the nearest free squadmate. Only AI on c's side that is up and not already
## looking after someone else counts (carrying a body doesn't count). With `wanted` items
## (a conscious casualty's call), only units carrying one of them count. Null if nobody.
static func responder_for(c: Soldier, wanted: Array[StringName] = []) -> Soldier:
	var team_medic: SquadAI = null
	var other_medic: SquadAI = null
	var nearest: SquadAI = null
	var other_d := INF
	var near_d := INF
	for n in c.get_tree().get_nodes_in_group(&"combatants"):
		var ai := SquadAI.of(n)
		if ai == null or ai.body == null or not ai._free_for(c) or not ai._cares_for(c) or not ai._carries_any(wanted):
			continue
		var d := ai.body.global_position.distance_to(c.body_point())
		if ai.escorting == c:
			return ai.body  # an HVT's escorts see to him first (a medic is pulled in as well)
		if ai.body.role == Roles.MEDIC:
			if c.fire_team >= 0 and ai.body.fire_team == c.fire_team and d <= MEDIC_FAR_M:
				team_medic = ai
			elif d < other_d:
				other_medic = ai
				other_d = d
		if d < near_d:
			nearest = ai
			near_d = d
	if team_medic:
		return team_medic.body
	var mate := SquadAI.of(c.buddy) if is_instance_valid(c.buddy) else null
	if mate and mate._free_for(c) and mate._carries_any(wanted):
		return mate.body
	if other_medic:
		return other_medic.body
	return nearest.body if nearest else null


## The medic who takes over casualty `c` from a carer who asked for one: a free medic on c's
## side carrying something in `wanted`, c's fire team's first unless it is far and the other
## one isn't. Null if none.
static func medic_for(c: Soldier, wanted: Array[StringName]) -> Soldier:
	var team: SquadAI = null
	var team_d := INF
	var other: SquadAI = null
	var other_d := INF
	for n in c.get_tree().get_nodes_in_group(&"combatants"):
		var ai := SquadAI.of(n)
		if ai == null or ai.body == null or ai.body.role != Roles.MEDIC or not ai._cares_for(c) or not ai._free_for(c) \
				or c.care_by == ai.body or wanted.is_empty() or not ai._carries_any(wanted):
			continue
		var d := ai.body.global_position.distance_to(c.body_point())
		if c.fire_team >= 0 and ai.body.fire_team == c.fire_team:
			team = ai
			team_d = d
		elif d < other_d:
			other = ai
			other_d = d
	if team and (team_d <= MEDIC_FAR_M or other == null):
		return team.body
	return other.body if other else (team.body if team else null)


## Up, set up, and not looking after anyone but `c` (a body being carried can be put down),
## and not leaving `c` to others after failing to reach them (_give_up_casualty).
func _free_for(c: Soldier) -> bool:
	return _ready_done and body != null and body != c and body.vitals.is_up() and not body.is_queued_for_deletion() \
		and (care == Care.NONE or care == Care.BODY or casualty == c) and not _skipping(c) \
		and (not escort_valid() or c == escorting)


## This unit couldn't reach `c` lately and leaves them to others for now.
func _skipping(c: Soldier) -> bool:
	return c != null and Soldier._now() < float(_skip.get(c.get_instance_id(), -1.0))


## Carries at least one of `ids`, loose or in a kit (true for none asked).
func _carries_any(ids: Array[StringName]) -> bool:
	if ids.is_empty():
		return true
	for id in ids:
		if Vitals.has_item(body.inventory, id) and _may_use(id):
			return true
	return false


## This unit may use `id`: anything, except that CPR and the defibrillator (stats.medic_only)
## are for medics among the AI.
func _may_use(id: StringName) -> bool:
	return body.role == Roles.MEDIC or not (ItemDB.has_item(id) and ItemDB.get_item(id).stats.get("medic_only", false))


## The casualty this unit should answer now, or null: one it is the responder for, or (a
## medic) one whose carer asked for a medic with something this medic carries. A medic
## prefers casualties in its own fire team.
func _find_casualty() -> Soldier:
	var best: Soldier = null
	var best_d := INF
	var best_tier := 99
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s == body or not _cares_for(s) or not needs_help(s):
			continue
		var carer := _carer_of(s)
		if carer == body:
			return s
		var hvt := Person.is_hvt(s)
		if hvt and not s.vitals.downed and _next_task(s, false).is_empty():
			continue  # nothing this unit can do for a conscious HVT
		if carer != null:
			var carer_ai := SquadAI.of(carer)
			if hvt and _takes_over_hvt(s, carer):
				pass  # a medic takes a wounded HVT over from whoever has him
			elif carer_ai == null or not carer_ai.wants_medic or medic_for(s, carer_ai.wanted) != body:
				continue  # someone is on it
		else:
			var ai := SquadAI.of(s)
			var asked: Array[StringName] = ai.wanted if ai and not s.vitals.downed else ([] as Array[StringName])
			if responder_for(s, asked) != body:
				continue
		var d := body.global_position.distance_to(s.global_position)
		if body.role == Roles.MEDIC and s.fire_team == body.fire_team:
			d *= 0.5
		if hvt and body.role == Roles.MEDIC:
			d *= HVT_MEDIC_PULL
		var tier := triage_tier(s)
		if tier < best_tier or (tier == best_tier and d < best_d):
			best = s
			best_d = d
			best_tier = tier
	return best


## How soon a triage card (Vitals.triage) puts a casualty in line: immediate first, then
## delayed and uncarded alike (the usual order), then minimal, expectant last.
static func triage_tier(s: Soldier) -> int:
	match s.vitals.triage():
		Vitals.TRIAGE_IMMEDIATE:
			return 0
		Vitals.TRIAGE_MINIMAL:
			return 2
		Vitals.TRIAGE_EXPECTANT:
			return 3
	return 1


## Who is really looking after `s`: a player who took hold of them, or an AI whose casualty
## they are. Null for nobody (or a stale claim).
static func _carer_of(s: Soldier) -> Soldier:
	var carer := s.care_by
	if not is_instance_valid(carer) or carer.is_queued_for_deletion() or not carer.vitals.is_up():
		return null
	var ai := SquadAI.of(carer)
	if ai == null:
		return carer if carer.carrying == s else null  # a player
	return carer if ai.casualty == s else null


## A friendly's dead body this unit should carry after the squad leader (out of contact):
## the body's battle buddy goes first, otherwise the nearest free non-medic.
func _find_body() -> Soldier:
	if body.faction != &"friendly" or squad == null or not is_instance_valid(squad.leader) or body.carrying != null:
		return null
	var best: Soldier = null
	var best_d := BODY_RECOVER_M
	for n in get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
		var s := n as Soldier
		if s == null or s.is_queued_for_deletion() or s.faction != body.faction or is_instance_valid(s.carried_by) \
				or _carer_of(s) != null:
			continue
		var d := body.global_position.distance_to(s.global_position)
		if d < best_d and _bearer_for(s) == body:
			best = s
			best_d = d
	return best


func _bearer_for(dead: Soldier) -> Soldier:
	var mate := SquadAI.of(dead.buddy) if is_instance_valid(dead.buddy) else null
	if mate and mate._can_bear(dead):
		return mate.body
	var best: Soldier = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var ai := SquadAI.of(n)
		if ai == null or ai.body == null or ai.body.faction != dead.faction or not ai._can_bear(dead):
			continue
		var d := ai.body.global_position.distance_to(dead.body_point()) * (1.0 if ai.body.role != Roles.MEDIC else 3.0)
		if d < best_d:
			best = ai.body
			best_d = d
	return best


## Free to carry a body: not looking after anyone, not carrying, out of contact and not busy
## with its own wounds.
func _can_bear(dead: Soldier) -> bool:
	return care == Care.NONE and _free_for(dead) and body.carrying == null and not in_contact() \
		and _self_care_score() <= 0.0 and not asking_for_medic()


func _do_care() -> void:
	if _candidate != null and (care == Care.NONE or care == Care.BODY) and _may_take(_candidate):
		_take_casualty(_candidate)
	_candidate = null
	if care == Care.NONE:
		var dead := _find_body() if not in_contact() else null
		if dead == null:
			_think_cd = 0.0
			return
		casualty = dead
		casualty.care_by = body
		care = Care.BODY
		_reset_reach()  # progress to the body is watched too (a player in the way: sidestep)
	if care == Care.BODY:
		_carry_body()
		return
	if not is_instance_valid(casualty) or casualty.is_queued_for_deletion() or casualty.vitals.is_dead() or casualty.care_by != body:
		_end_care()  # gone, dead, or a medic took over
		_think_cd = 0.0
		return
	var contact := in_contact()
	match care:
		Care.REACH:
			_care_reach(contact)
		Care.DRAG:
			if body.carrying != casualty:
				care = Care.TREAT
			elif _has_cover and not _at_cover():
				_go(_cover_point, false)
			else:
				_has_destination = false
				body.server_put_down()
				care = Care.TREAT
		Care.TREAT:
			_care_treat(contact)
		Care.GUARD:
			# Stay with them and protect them; back to treating once it's quiet, or once
			# there's something to do that cover allows.
			if not contact or not _next_task(casualty, _care_exposed(contact)).is_empty():
				care = Care.TREAT
			else:
				_fight(casualty.body_point(), 3.0)
		Care.CARRY:
			_care_carry(contact)


## `c` still needs help and is still free for this unit to take (nobody else got there first,
## or its carer asked for a medic and this unit is the one).
func _may_take(c: Soldier) -> bool:
	if not needs_help(c):
		return false
	var carer := _carer_of(c)
	if carer == null or carer == body:
		return true
	if Person.is_hvt(c) and _takes_over_hvt(c, carer):
		return true
	var carer_ai := SquadAI.of(carer)
	return carer_ai != null and carer_ai.wants_medic and medic_for(c, carer_ai.wanted) == body


## This unit (a free medic) takes wounded HVT `c` over from `carer`, who isn't a medic: the
## escorts' care is a stopgap until a medic is there.
func _takes_over_hvt(c: Soldier, carer: Soldier) -> bool:
	return body.role == Roles.MEDIC and carer != body and carer.role != Roles.MEDIC and _free_for(c) and _cares_for(c)


## Takes `c` on (from nobody, or from a carer who asked for a medic).
func _take_casualty(c: Soldier) -> void:
	if care != Care.NONE:
		_end_care()
	casualty = c
	c.care_by = body
	_start_reach()
	_smoke_used = false
	_has_cover = false
	_asked_medic = false
	_answered = false
	wants_medic = false
	wanted.clear()
	_failures.clear()
	var callouts := Callouts.of(body)
	if callouts:
		callouts.answer_casualty(body, c, false)


## Sets off toward the casualty (Care.REACH), watching for progress from here.
func _start_reach() -> void:
	care = Care.REACH
	_reset_reach()


## Starts watching progress toward the casualty or body afresh (_reach_progress).
func _reset_reach() -> void:
	_reach_best = INF
	_reach_progress_at = Soldier._now()
	_detour_until = -1.0
	_detour_next = -1.0


## Going to the casualty, under fire as well. A casualty down in the open gets smoke between
## them and the threat as soon as they're in throwing range. Pinned down meanwhile (the
## casualty can't be reached alive yet), this unit holds, smokes and puts suppressive fire on
## the threat first. At the casualty: one lying in the open is dragged to cover, otherwise
## treatment starts.
func _care_reach(contact: bool) -> void:
	var d := _flat_distance(casualty.body_point())
	if body.carrying == casualty:
		care = Care.CARRY
		return
	var exposed := contact and casualty.vitals.downed and not _sheltered(casualty)
	if exposed and not _smoke_used and d <= SMOKE_RANGE_M:
		if body.inventory.count_of(SCREEN_SMOKE) <= 0:
			_smoke_used = true  # nothing to screen them with
		elif _throw(SCREEN_SMOKE, casualty.body_point() + (body.threat_pos - casualty.body_point()).normalized() * 4.0):
			_smoke_used = true
	if exposed and body.suppression >= PINNED and d > CASUALTY_REACH:
		_suppressing = true
		_reach_progress_at = Soldier._now()  # waiting here isn't being stuck
		_has_destination = false
		body.want_crouch = true
		return
	if not _reach_progress(d, casualty.body_point(), _give_up_casualty):
		return  # gave up: the next responder takes them
	_go(_detour if Soldier._now() < _detour_until else casualty.body_point(), true)
	if d > CASUALTY_REACH:
		return
	_has_destination = false
	# (Never lift someone another is treating: it cut the Captain's IV short, P0164.)
	if exposed and not is_instance_valid(casualty.carried_by) and not casualty.vitals.is_healing():
		var spot: Variant = find_cover(body.global_position, 10.0)
		if spot != null and body.server_pick_up_body(casualty, Soldier.DRAG):
			_cover_point = spot
			_has_cover = true
			care = Care.DRAG
			return
	care = Care.TREAT


## Watches the approach to `target` (a casualty, or a body to scavenge) `d` metres away. No
## closer for REACH_STUCK_S (something the navmesh doesn't know about is in the way, such as
## a player) means a sidestep, alternating sides, with a try at the direct way in between;
## no closer for REACH_GIVE_UP_S calls `give_up` (handing the casualty on, leaving the body).
## False once this unit gave up.
func _reach_progress(d: float, target: Vector3, give_up: Callable) -> bool:
	var now := Soldier._now()
	if d < _reach_best - REACH_PROGRESS_M or d <= CASUALTY_REACH:
		_reach_best = minf(d, _reach_best)
		_reach_progress_at = now
		return true
	if now - _reach_progress_at >= REACH_GIVE_UP_S:
		give_up.call()
		return false
	if now - _reach_progress_at >= REACH_STUCK_S and now >= _detour_next:
		_detour_side = -_detour_side
		_detour_until = now + DETOUR_S
		_detour_next = now + DETOUR_S * 2.5
		var to := target - body.global_position
		to.y = 0.0
		var side := Vector3(-to.z, 0.0, to.x).normalized() * _detour_side
		var map := body.get_world_3d().navigation_map
		_detour = NavigationServer3D.map_get_closest_point(map, body.global_position + side * DETOUR_M + to.normalized() * 0.3)
	return true


## Couldn't get to the casualty: lets go of them so the next responder (responder_for)
## takes them, and leaves them to others for REACH_SKIP_S.
func _give_up_casualty() -> void:
	var now := Soldier._now()
	for id: int in _skip.keys():
		if float(_skip[id]) <= now:
			_skip.erase(id)
	if is_instance_valid(casualty):
		_skip[casualty.get_instance_id()] = now + REACH_SKIP_S
	_end_care()
	_has_destination = false
	_think_cd = 0.0


## Beside the casualty: treats them item by item in the care order (only massive bleeding
## while either of them is exposed to the threat). Once nothing more can be done: a conscious
## casualty is left to it (or guarded until cover or quiet allows the rest); an unconscious one
## is guarded in contact, otherwise watched over where they lie or carried after the squad
## (_should_carry) until they wake on their own.
func _care_treat(contact: bool) -> void:
	if body.carrying == casualty:
		body.server_put_down()
		if body.carrying == casualty:
			return  # still lowering them off the shoulder
	if _flat_distance(casualty.body_point()) > CASUALTY_REACH + 1.0:
		_start_reach()  # a conscious casualty moved, or the body slid
		return
	_has_destination = false
	body.want_crouch = true
	_face(casualty.body_point())
	var now := Soldier._now()
	if _treat_until >= 0.0 or now < body._busy_until:
		return  # an item is going on
	var exposed := _care_exposed(contact)
	var task := _next_task(casualty, exposed)
	if not task.is_empty():
		_start_treatment(casualty, task)
		return
	# Nothing more this unit can do for them now.
	if not casualty.vitals.downed:
		if exposed and not _next_task(casualty, false).is_empty():
			care = Care.GUARD  # the rest once in cover or quiet
		else:
			_end_care()  # conscious and patched up as far as this unit can
		return
	if contact:
		care = Care.GUARD
		return
	_want_medic()
	if _should_carry():
		care = Care.CARRY


## Treating `casualty` counts as under fire: in contact, with the casualty or this unit in
## the open to the last known threat. Behind cover the whole care order goes on, even in a
## firefight.
func _care_exposed(contact: bool) -> bool:
	return contact and (not _sheltered(casualty) or not _cover_protects(body.global_position))


## An unconscious casualty with nothing left to treat goes with the squad: one who won't
## wake soon (past the wound model's unconscious blood loss), or any once the squad leader is
## more than STAY_WITH_M away. Otherwise they're watched over where they lie.
func _should_carry() -> bool:
	if _holds_for_medic():
		return false
	if Person.is_hvt(casualty):
		return true  # an HVT goes with the squad, not left lying
	var ccp: Variant = squad.ccp_point() if squad else null
	if ccp != null and _friendly():
		return casualty.body_point().distance_to(ccp) > LAY_NEAR_M + 1.0  # "Bring casualties here"
	if _friendly() and order == Squad.Order.MOVE and _lay_spot != null and _flat_between(casualty.body_point(), _lay_spot) <= LAY_NEAR_M + 1.0:
		return false  # laid where the order sent them: they stay while it stands (queue 16)
	if 1.0 - casualty.vitals.blood_fraction() >= WoundModel.UNCONSCIOUS_LOST:
		return true
	var leader: Soldier = squad.leader if squad and is_instance_valid(squad.leader) else null
	return leader != null and leader != casualty and leader.global_position.distance_to(casualty.body_point()) > STAY_WITH_M


## Still bleeding with nothing this unit can do about it (a medic-only clamp, no gauze or
## tourniquet left) and a medic who has it is free: hold beside them and call the medic,
## rather than carry them bleeding after the leader (cghath's test, P0164 queue 14).
func _holds_for_medic() -> bool:
	if casualty.vitals.bleed_rate() <= 0.0:
		return false
	if wanted.is_empty():
		wanted = _missing_items(casualty)
	return medic_for(casualty, wanted) != null


## Carrying an unconscious casualty after the squad leader until they wake on their own. In
## contact they're dragged to cover (or guarded where they lie); something new to treat, or
## waking up, sends this unit back to treating them.
func _care_carry(contact: bool) -> void:
	if contact:
		if body.carrying == casualty:
			body._set_carry_mode(Soldier.DRAG, &"grab")
			var spot: Variant = find_cover(body.global_position, 10.0)
			_has_cover = spot != null
			if spot != null:
				_cover_point = spot
			care = Care.DRAG
		else:
			care = Care.GUARD
		return
	if not casualty.vitals.downed or not _next_task(casualty, false).is_empty():
		care = Care.TREAT  # woke up, or there's something new to do (an item handed over)
		return
	if _holds_for_medic():
		if body.carrying == casualty:
			body.server_put_down()  # a bleed opened up on the way: put them down for the medic
		_want_medic()
		care = Care.TREAT
		return
	var leader: Soldier = squad.leader if squad and is_instance_valid(squad.leader) else null
	if leader == null or casualty == leader or body.faction != &"friendly":
		# No one to follow (or the lead is down): keep them safe where they are.
		if body.carrying == casualty:
			body.server_put_down()
		_has_destination = false
		body.want_crouch = true
		return
	# Captain (P0164 queue 16): ordered to move while carrying, go there and lay them down at
	# the safest spot nearby (cover from the last known threat). "Bring casualties here" (queue
	# 12) does the same at the squad's casualty collection point (Squad.ccp), even following.
	var ccp: Variant = squad.ccp_point() if squad else null
	var to_spot := order == Squad.Order.MOVE or ccp != null
	if to_spot:
		var goal: Vector3 = ccp if ccp != null else _move_point
		if _lay_spot == null or _lay_for.distance_to(goal) > LAY_NEAR_M:
			_lay_for = goal
			var spot: Variant = find_cover(goal, LAY_DOWN_M)
			_lay_spot = spot if spot != null else NavigationServer3D.map_get_closest_point(body.get_world_3d().navigation_map, goal)
		var lay: Vector3 = _lay_spot
		var at := casualty.body_point()
		if body.carrying != casualty and Vector2(at.x - lay.x, at.z - lay.z).length() <= LAY_NEAR_M:
			_has_destination = false  # laid down where ordered: stay with them
			body.want_crouch = true
			return
		if body.carrying == casualty and _flat_distance(lay) <= 1.0:
			body.server_put_down()
			_has_destination = false
			body.want_crouch = true
			return
	if body.carrying != casualty:
		if casualty.vitals.is_healing():
			_has_destination = false  # someone is treating them: wait, don't lift them away (P0164)
			return
		if _flat_distance(casualty.body_point()) <= CASUALTY_REACH and body.server_pick_up_body(casualty, Soldier.CARRY):
			_callouts_carrying(false)
		else:
			_go(casualty.body_point(), true)
		return
	_go(_lay_spot if to_spot else squad.follow_point(body))


## Out of contact: picks up a fallen friendly's body and carries it after the squad leader.
func _carry_body() -> void:
	if in_contact() or not is_instance_valid(casualty) or casualty.is_queued_for_deletion() \
			or (is_instance_valid(casualty.carried_by) and casualty.carried_by != body) or squad == null or not is_instance_valid(squad.leader):
		_end_care()
		return
	if body.carrying != casualty:
		var looter := SquadAI.of(casualty.scavenged_by) if is_instance_valid(casualty.scavenged_by) else null
		if looter and looter != self and looter.loot_body == casualty and looter.body.vitals.is_up():
			# Someone is cross-loading from the body: wait beside it until they're done.
			if _flat_distance(casualty.body_point()) > CASUALTY_REACH + 1.5:
				_go(casualty.body_point(), true)
			else:
				_has_destination = false
			return
		var d := _flat_distance(casualty.body_point())
		if d <= CASUALTY_REACH and body.server_pick_up_body(casualty, Soldier.CARRY):
			_callouts_carrying(true)
		elif _reach_progress(d, casualty.body_point(), _give_up_casualty):
			# Something the navmesh doesn't know (a player) in the way: sidestep (casualty R0210).
			_go(_detour if Soldier._now() < _detour_until else casualty.body_point(), true)
		return
	_go(squad.follow_point(body))


func _callouts_carrying(dead: bool) -> void:
	var callouts := Callouts.of(body)
	if callouts:
		callouts.carrying(body, casualty, dead)


func _end_care() -> void:
	if is_instance_valid(casualty):
		if body.carrying == casualty:
			body.release_carried()
		if casualty.care_by == body:
			casualty.care_by = null
		var their := SquadAI.of(casualty)
		if their and casualty.vitals.is_up():
			their._medic_called_at = -1000.0  # answered; they call again if they still need it
	elif body.carrying != null and not is_instance_valid(body.carrying):
		body.release_carried()
	casualty = null
	care = Care.NONE
	_has_cover = false
	wants_medic = false
	wanted.clear()


# --- HVT escort ---------------------------------------------------------------

## Escorts HVT `h` (Squad.order_escort); null stops.
func set_escort(h: Soldier, order_index := 0) -> void:
	escorting = h
	escort_order = order_index
	_react_at = -1.0
	if h != null:
		if loot_body != null:
			_end_scavenge()
		_think_cd = 0.0


## The HVT this unit escorts is still there to escort: alive and not delivered.
func escort_valid() -> bool:
	if not is_instance_valid(escorting) or escorting.is_queued_for_deletion() or escorting.vitals.is_dead():
		return false
	return not bool(Person.state(escorting).get("delivered", false))


## The AI escorting HVT `h`, up, in the order they were given it (the first leads him).
static func escorts_of(h: Soldier) -> Array[SquadAI]:
	var out: Array[SquadAI] = []
	if h == null or not h.is_inside_tree():
		return out
	for n in h.get_tree().get_nodes_in_group(&"combatants"):
		var ai := SquadAI.of(n)
		if ai and ai.escorting == h and ai.body != null and ai.body.vitals.is_up() and not ai.body.is_queued_for_deletion():
			out.append(ai)
	out.sort_custom(func(a: SquadAI, b: SquadAI) -> bool: return a.escort_order < b.escort_order)
	return out


## An HVT the players' side holds or guards: a hostage or friendly HVT, a captive, one who is
## down, or one escorted or carried by the squad. A hostile HVT still running free is not.
static func in_our_hands(h: Soldier, faction: StringName) -> bool:
	if faction != &"friendly" or not Person.is_hvt(h) or h.vitals.is_dead():
		return false
	if Person.side_of(h) == Person.FRIENDLY or Person.is_captive(h) or not h.vitals.is_up():
		return true
	if is_instance_valid(h.carried_by) and h.carried_by.faction == faction:
		return true
	return not escorts_of(h).is_empty()


## Someone this unit looks after medically: its own side, or an HVT in its side's hands.
func _cares_for(s: Soldier) -> bool:
	return s.faction == body.faction or in_our_hands(s, body.faction)


func _do_escort() -> void:
	var h := escorting
	var now := Soldier._now()
	if Person.side_of(h) == Person.HOSTILE and not Person.is_captive(h) and h.vitals.is_up() and not is_instance_valid(h.carried_by):
		_chase(h, now)
		return
	_react_at = -1.0
	var layer := PeopleLayer.find(body)
	var st := Person.state(h)
	var escorts := escorts_of(h)
	var handler := not escorts.is_empty() and escorts[0] == self
	if handler and layer and Person.leadable(h) and String(st.get("order", "")) in ["", "follow"]:
		var led := String(st.get("led_by", ""))
		var leader := layer.get_parent().get_node_or_null(NodePath(led)) as Soldier if led != "" else null
		if leader == null or not leader.vitals.is_up() or (leader.is_ai() and leader != body):
			layer.server_lead(body, h)
	var anchor := h.global_position
	if fighting():
		var to_threat := body.threat_pos - anchor
		to_threat.y = 0.0
		_fight(anchor + (to_threat.normalized() * ESCORT_GUARD_M if to_threat.length() > 0.5 else Vector3.ZERO), ESCORT_LEASH_M)
		return
	if handler and layer and String(Person.state(h).get("led_by", "")) == layer.key_of(body):
		if _flat_distance(anchor) > ESCORT_WAIT_M:
			_has_destination = false  # let him catch up
		else:
			_go(squad.follow_point(body) if squad else body.global_position)  # he follows this unit
		return
	var ref := squad.leader.global_position if squad and is_instance_valid(squad.leader) else body.global_position
	var back := anchor - ref
	back.y = 0.0
	var spot := anchor + (back.normalized() if back.length() > 0.3 else Vector3.BACK) * ESCORT_GUARD_M
	if _flat_distance(spot) > ARRIVE + 0.5:
		_go(spot, _flat_distance(spot) > RUN_DISTANCE)
	else:
		_has_destination = false


## Its HVT bolted: after a reaction time, run him down and grab him (he gives up again).
func _chase(h: Soldier, now: float) -> void:
	if _react_at < 0.0:
		_react_at = now + lerpf(ESCORT_REACT_S.x, ESCORT_REACT_S.y, combat) + (ESCORT_SUPPRESSED_S if body.suppression >= SUPPRESSED else 0.0)
	if now < _react_at or body.suppression >= PINNED or body.stunned_s > 0.0:
		_has_destination = false
		return
	_go(h.global_position, true)
	if _flat_distance(h.global_position) > GRAB_M or now < _grab_next:
		return
	_grab_next = now + GRAB_RETRY_S
	if randf() >= minf((GRAB_CHANCE + GRAB_SKILL * combat) * grab_scale, 1.0):
		return  # he twisted free
	var layer := PeopleLayer.find(body)
	if layer:
		layer.server_surrender(h, "grabbed by %s" % body.display_name())
		grabs += 1
		_react_at = -1.0
		_think_cd = 0.0


# --- Scavenging -------------------------------------------------------------

## How much going through a body scores now (0: not now). Out of contact for
## SCAVENGE_CALM_S, free (no casualty, nothing carried, no wounds to see to), and for a
## friendly, following the squad and allowed to; an order skips the wait and the need.
func _scavenge_score(contact: bool) -> float:
	_loot_candidate = null
	if contact or care != Care.NONE or body.carrying != null or _self_care_score() > 0.0 or asking_for_medic() or escort_valid():
		return 0.0
	if is_instance_valid(scavenge_order) and _may_scavenge(scavenge_order, true):
		_loot_candidate = scavenge_order
		return SCAVENGE_ORDER_SCORE
	scavenge_order = null
	if body.faction == &"friendly" and (not scavenge_allowed or order != Squad.Order.FOLLOW):
		return 0.0
	if Soldier._now() - _last_contact < SCAVENGE_CALM_S:
		return 0.0
	if intent == Intent.SCAVENGE and loot_body != null and _may_scavenge(loot_body):
		_loot_candidate = loot_body
		return _loot_score  # carry on with this body
	var best_value := 0.0
	for n in get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
		var dead := n as Soldier
		if dead == null or not _may_scavenge(dead) or Soldier._now() < float(_looted.get(dead.get_instance_id(), -1.0)):
			continue
		var d := body.global_position.distance_to(dead.global_position)
		if d > SCAVENGE_RANGE_M:
			continue
		var worth := Scavenge.value(body, dead, _calm_for_armor()) - d * 0.002  # nearer first
		if worth >= SCAVENGE_MIN and worth > best_value:
			best_value = worth
			_loot_candidate = dead
	if _loot_candidate == null:
		return 0.0
	_loot_score = SCAVENGE_SCORE + SCAVENGE_NEED_SCORE * minf(best_value, 1.0)
	return _loot_score


## Whether this unit may go through `dead`: a dead body nobody carries and nobody else is
## going through, not a dead player's (their gear waits for them, under a gear marker),
## and for a friendly within SCAVENGE_LEASH_M of the squad leader unless `ordered` to it.
func _may_scavenge(dead: Soldier, ordered := false) -> bool:
	if dead == null or not is_instance_valid(dead) or dead.is_queued_for_deletion() or dead == body \
			or not dead.vitals.is_dead() or dead.has_gear_marker or not dead.has_gear() or is_instance_valid(dead.carried_by):
		return false
	var other := dead.scavenged_by
	if is_instance_valid(other) and other != body and other.vitals.is_up() and SquadAI.of(other) and SquadAI.of(other).loot_body == dead:
		return false
	if not ordered and body.faction == &"friendly" and squad and is_instance_valid(squad.leader) and squad.leader != body \
			and dead.global_position.distance_to(squad.leader.global_position) > SCAVENGE_LEASH_M:
		return false
	return true


## Long enough out of contact to swap armor (a plate takes several seconds with the carrier open).
func _calm_for_armor() -> bool:
	return Soldier._now() - _last_contact >= ARMOR_CALM_S


## Goes to the body, kneels at it and takes one thing at a time (Scavenge.best_pick), each
## taking its time; the item moves when that time is up. Done when nothing on it is worth
## taking any more (or it's gone, or someone else carries it off).
func _do_scavenge() -> void:
	if loot_body != null and _loot_candidate != null and _loot_candidate == scavenge_order and loot_body != _loot_candidate:
		_end_scavenge()  # ordered to another body
	if loot_body == null:
		if _loot_candidate == null:
			_think_cd = 0.0
			return
		loot_body = _loot_candidate
		loot_body.scavenged_by = body
		_loot_pick = {}
		_loot_until = -1.0
		_reach_best = INF
		_reach_progress_at = Soldier._now()
		_detour_until = -1.0
		var callouts := Callouts.of(body)
		if callouts:
			callouts.scavenging(body, loot_body)
	if not _may_scavenge(loot_body, loot_body == scavenge_order):
		_end_scavenge()
		_think_cd = 0.0
		return
	var d := _flat_distance(loot_body.body_point())
	if d > CASUALTY_REACH:
		if _reach_progress(d, loot_body.body_point(), _give_up_body):
			_go(_detour if Soldier._now() < _detour_until else loot_body.body_point(), false)
		return
	_has_destination = false
	body.want_crouch = true
	body.want_aim = false
	var now := Soldier._now()
	if _loot_until >= 0.0:
		if now < _loot_until:
			return
		Scavenge.apply(body, loot_body, _loot_pick)
		_loot_until = -1.0
		_loot_pick = {}
	var ordered := scavenge_order == loot_body
	var pick := Scavenge.best_pick(body, loot_body, _calm_for_armor(), 0.001 if ordered else SCAVENGE_KEEP)
	if pick.is_empty():
		_looted[loot_body.get_instance_id()] = now + SCAVENGE_SKIP_S
		if ordered:
			scavenge_order = null
		_end_scavenge()
		_think_cd = 0.0
		return
	_loot_pick = pick
	_loot_until = now + float(pick.seconds)
	body.model.server_loot(loot_body, float(pick.seconds) >= 3.0)


## Couldn't get to the body (a player standing in the way, say): leaves it for
## SCAVENGE_SKIP_S, and an order to it lapses.
func _give_up_body() -> void:
	if is_instance_valid(loot_body):
		_looted[loot_body.get_instance_id()] = Soldier._now() + SCAVENGE_SKIP_S
		if scavenge_order == loot_body:
			scavenge_order = null
	_end_scavenge()
	_has_destination = false
	_think_cd = 0.0


func _end_scavenge() -> void:
	if is_instance_valid(loot_body) and loot_body.scavenged_by == body:
		loot_body.scavenged_by = null
	loot_body = null
	_loot_pick = {}
	_loot_until = -1.0


## The next treatment this unit can give `c` now, in the care order (under fire: massive
## bleeding only), with an item it carries (loose or in a kit) that hasn't failed TREAT_TRIES
## times, not one the casualty is doing on themselves right now, and (on itself) not one a
## medic keeps for the squad (_kept_for_squad), nor an IV or IO on itself; {} for none. Where
## several items would do, the task's "item" becomes the first one carried (Vitals.pick_item),
## out of the casualty's own kit first ("their_kit": _pick_for).
func _next_task(c: Soldier, under_fire: bool) -> Dictionary:
	var conscious := c.vitals.is_up() or c.vitals.why_unconscious().has(&"pain")  # morphine wakes one out from pain
	var their := SquadAI.of(c) if c != body else null
	for task in plan_care(c.vitals.care_needed(), under_fire, conscious):
		if their and their._treat_until >= 0.0 and their._treat_key == _task_key(c, task):
			continue
		if String(task.kind) == "pain" and c.vitals.pain() < MORPHINE_PAIN:
			continue
		var pick := _pick_for(c, task)
		var item: StringName = pick.item
		if item == &"" or (c == body and Vitals.needs_other_hands(item)):
			continue
		if not _may_use(item):
			continue  # CPR and shocks: players and medics only
		if c == body and _kept_for_squad(item, String(task.kind)):
			continue
		var kind := String(task.kind)
		if kind not in RESTART_KINDS and int(_failures.get(_task_key(c, task), 0)) >= (ACCESS_TRIES if kind == "access" else TREAT_TRIES):
			continue
		var chosen := task.duplicate()
		chosen.item = item
		chosen.their_kit = pick.theirs
		return chosen
	return {}


## The item for `task` on casualty `c`: out of c's own kit first, then this unit's (Captain,
## P0164 queue 17: a carer uses the casualty's IFAK before their own, so their own is still
## there for the next casualty, or for themselves). On itself, its own. {"item" (&"" for
## none), "theirs" (it comes out of c's kit)}.
func _pick_for(c: Soldier, task: Dictionary) -> Dictionary:
	if c != body:
		var theirs := Vitals.pick_item(task, c.inventory)
		if theirs != &"" and _may_use(theirs):
			return {"item": theirs, "theirs": true}
	return {"item": Vitals.pick_item(task, body.inventory), "theirs": false}


## Items this unit lacks (or, on itself, keeps for the squad) for what `c` still needs once
## safe, counting what c carries (_pick_for).
func _missing_items(c: Soldier) -> Array[StringName]:
	var out: Array[StringName] = []
	for task in plan_care(c.vitals.care_needed(), false, c.vitals.is_up() or c.vitals.why_unconscious().has(&"pain")):
		var item: StringName = _pick_for(c, task).item
		var lacks := item == &"" or not _may_use(item) or (c == body and (Vitals.needs_other_hands(item) or _kept_for_squad(item, String(task.kind))))
		if not lacks:
			continue
		for option in Vitals.task_items(task):  # a medic carrying any of them will do
			if option not in out:
				out.append(option)
	return out


## A medic keeps `item` for the squad instead of using it on itself while nobody else on its
## side who is up carries one, unless it's for massive bleeding (a medic who bleeds out treats
## nobody). What it keeps, it calls another medic for.
func _kept_for_squad(item: StringName, kind: String) -> bool:
	if body.role != Roles.MEDIC or kind in MASSIVE_BLEED_KINDS:
		return false
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s != body and s.faction == body.faction and not s.is_queued_for_deletion() and s.vitals.is_up() \
				and s.inventory.medical_count(item) > 0:
			return false
	return true


## Nothing more this unit can do for its unconscious casualty: asks for a medic who has
## what's missing.
func _want_medic() -> void:
	wanted = _missing_items(casualty)
	wants_medic = not wanted.is_empty()  # one who lacks nothing has nobody to call
	if wants_medic and not _asked_medic:
		_asked_medic = true
		var callouts := Callouts.of(body)
		if callouts:
			callouts.need_medic(body, casualty)


static func _task_key(c: Soldier, task: Dictionary) -> String:
	return "%s|%s|%s" % [c.name, task.part, task.kind]


static func _count_tasks(c: Soldier, key: String) -> int:
	var n := 0
	for task in c.vitals.care_needed():
		if _task_key(c, task) == key:
			n += 1
	return n


## Treats `target` (a casualty or this body) with one item through Soldier._server_treat,
## the host request players use too.
func _start_treatment(target: Soldier, task: Dictionary) -> void:
	var item := ItemDB.get_item(StringName(task.item))
	var seconds := body.treat_seconds(target, item) if item else 4.0
	_treat_target = target
	_treat_key = _task_key(target, task)
	_treat_before = _count_tasks(target, _treat_key)
	_treat_until = Soldier._now() + seconds + TREAT_MARGIN_S
	body._server_treat.rpc_id(1, target.get_path(), StringName(task.item), StringName(task.part), false, bool(task.get("their_kit", false)))
	if target != body and not _answered:
		_answered = true
		var callouts := Callouts.of(body)
		if callouts:
			callouts.answer_casualty(body, target, true)


## A treatment's time is up: if the task is still there as often as before, it failed.
func _finish_treatment() -> void:
	if _treat_key != "" and is_instance_valid(_treat_target) and _count_tasks(_treat_target, _treat_key) >= _treat_before:
		_failures[_treat_key] = int(_failures.get(_treat_key, 0)) + 1
	_treat_until = -1.0
	_treat_key = ""
	_think_cd = 0.0


## Under cover from the last known threat, lying down.
func _sheltered(c: Soldier) -> bool:
	return not Throwables.clear_line(body.get_world_3d(), body.threat_pos + Vector3.UP * 1.5, c.global_position + Vector3.UP * 0.4)


func _face(point: Vector3) -> void:
	var d := point - body.global_position
	if Vector2(d.x, d.z).length() > 0.2:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-d.x, -d.z), 0.2)


# --- Morale ---------------------------------------------------------------

## Where morale settles with nothing going on: the more disciplined, the steadier.
func _morale_base() -> float:
	return lerpf(0.6, 1.0, clampf(discipline, 0.0, 1.0))


## The level morale heads for now (see MORALE_NEAR_M).
func morale_target() -> float:
	var t := _morale_base()
	var up := 0
	var down := 0
	var seen := {}
	for group: StringName in [&"combatants", Soldier.DEAD_GROUP]:
		for n in get_tree().get_nodes_in_group(group):
			var s := n as Soldier
			if s == null or s == body or s.faction != body.faction or s.is_queued_for_deletion() or seen.has(s) \
					or s.global_position.distance_to(body.global_position) > MORALE_NEAR_M:
				continue
			seen[s] = true
			if s.vitals.is_up():
				up += 1
			else:
				down += 1
	t -= MORALE_PER_DOWN * down
	t -= MORALE_INJURY * body.vitals.injury()
	t -= MORALE_SUPPRESSION * body.suppression
	var known := _aware.values().filter(func(a: float) -> bool: return a >= 1.0).size()
	if known > up + 1:
		t -= MORALE_OUTNUMBERED * (known - up - 1)
	var lead: Soldier = squad.leader if squad and is_instance_valid(squad.leader) else null
	if lead and lead != body and lead.vitals.is_up() and lead.global_position.distance_to(body.global_position) <= MORALE_LEADER_M:
		t += MORALE_LEADER
	return clampf(t, 0.0, 1.0)


func _update_morale(dt: float) -> void:
	var t := morale_target()
	morale = move_toward(morale, t, (MORALE_FALL_PER_S if t < morale else MORALE_RISE_PER_S) * dt)
	var state := "broken" if morale < MORALE_BROKEN else ("shaken" if morale < MORALE_SHAKEN else "steady")
	if state != _morale_state:
		print("[tactics] %s %s (morale %.2f)" % [body.name, state, morale])
		_morale_state = state
		if state != "broken":
			_fall_back_point = null


func broken() -> bool:
	return morale < MORALE_BROKEN


## Falls back (Intent.FALL_BACK): to cover FALL_BACK_M away from the threat (a friendly: toward
## the leader), then fights from there.
func _do_fall_back() -> void:
	if _fall_back_point == null:
		var away := body.global_position - body.threat_pos
		away.y = 0.0
		var lead: Soldier = squad.leader if squad and is_instance_valid(squad.leader) else null
		var p := lead.global_position if _friendly() and lead and lead != body \
			else body.global_position + (away.normalized() if away.length() > 0.1 else -body.global_basis.z) * FALL_BACK_M
		var spot: Variant = find_cover(p, FALL_BACK_COVER_M)
		_fall_back_point = spot if spot != null else NavigationServer3D.map_get_closest_point(body.get_world_3d().navigation_map, p)
	var point: Vector3 = _fall_back_point
	if _flat_distance(point) > ARRIVE + 0.5:
		_go(point, true)
	else:
		_fight(point, 3.0)


# --- Self-care ------------------------------------------------------------

## How much this unit wants to look after itself (0 for not at all): its own arterial bleed
## at once (even under fire), the rest out of contact or in cover, or staying still while a
## squadmate treats it.
func _self_care_score() -> float:
	if _treat_until >= 0.0 and _treat_target == body:
		return 0.98  # finish what you started
	if _being_treated():
		return 0.92
	var own := _self_task()
	if own.is_empty():
		return 0.0
	if String(own.kind) in UNDER_FIRE_KINDS or Soldier._now() < _heal_until:
		return 0.97  # bleeding out, or told to patch up now
	return 0.75 if in_contact() else 0.62


## What this unit can do for itself right now (see _self_care_score), or {}.
func _self_task() -> Dictionary:
	if not body.vitals.is_up():
		return {}
	return _next_task(body, in_contact() and not _at_cover())


func _do_self_care() -> void:
	_has_destination = false
	body.want_crouch = true
	if _being_treated() or _treat_until >= 0.0 or Soldier._now() < body._busy_until:
		return
	var task := _self_task()
	if not task.is_empty():
		_start_treatment(body, task)
		return
	_think_cd = 0.0


## A squadmate is with this conscious unit to treat it: hold still.
func _being_treated() -> bool:
	var carer := body.care_by
	if not is_instance_valid(carer) or not carer.vitals.is_up():
		return false
	var ai := SquadAI.of(carer)
	return ai != null and ai.casualty == body and ai.care in [Care.REACH, Care.TREAT] \
		and _flat_distance(carer.global_position) <= BEING_TREATED_M


## A conscious wounded unit that needs what it doesn't carry (or, a medic, keeps for the
## squad) calls "Medic!" (at most every MEDIC_CALL_S) and lists what it needs in `wanted`.
func _maybe_call_medic() -> void:
	if care != Care.NONE and care != Care.BODY:
		return
	var now := Soldier._now()
	if now - _medic_called_at < MEDIC_CALL_S or _being_treated() or not body.vitals.is_up():
		return
	var missing := _missing_items(body)
	if missing.is_empty():
		return
	if responder_for(body, missing) == null:
		return  # nobody free carries any of it: no use shouting yet
	wanted = missing
	_medic_called_at = now
	var callouts := Callouts.of(body)
	if callouts:
		callouts.medic_call(body)


# --- Tactics ---------------------------------------------------------------

## The squad evaluator's task for this unit (SquadTactics). The same task again (its "id" and
## kind) only refreshes it, keeping its progress; {} clears it.
func set_task(t: Dictionary) -> void:
	if t.is_empty():
		task = {}
		return
	if task.get("id") == t.get("id") and task.get("kind") == t.get("kind"):
		for k: Variant in t:
			task[k] = t[k]
		return
	task = t.duplicate()
	task["since"] = Soldier._now()


## A command-menu tactic order (Squad.order_suppress and the rest); {} cancels it. It wins over
## the squad's own tactics until it ends or a movement order replaces it.
func give_tactic(t: Dictionary) -> void:
	ordered = t.duplicate()
	if not t.is_empty():
		ordered["since"] = Soldier._now()
		set_escort(null)
		_has_cover = false
		_think_cd = 0.0


## "Heal up": look after your own wounds first for HEAL_ORDER_S, even in contact.
func order_heal() -> void:
	_heal_until = Soldier._now() + HEAL_ORDER_S
	_think_cd = 0.0


## The tactic this unit works to now: its order, else the evaluator's task (a friendly only
## moves for one while following its lead: a Hold or Move order keeps it where it was put).
func _tactic() -> Dictionary:
	if not ordered.is_empty():
		if ordered.has("until") and Soldier._now() >= float(ordered.until):
			ordered = {}
		else:
			return ordered
	if task.is_empty():
		return task
	if _friendly() and order != Squad.Order.FOLLOW and StringName(task.kind) in MOVING_TACTICS:
		return {}
	return task


## Share of a full load (`full_mags` magazines) of ammunition for the weapon in hand, 0..1 (1 if
## it takes none).
func ammo_share(full_mags: float) -> float:
	var weapon := body.active_weapon()
	if weapon == null or weapon.type != "weapon":
		return 1.0
	var mag := _mag_size(weapon)
	if mag <= 0:
		return 1.0
	var rounds := body.inventory.rounds_in(body.active_slot) + body.inventory.spare_rounds(Soldier._ammo_of(weapon))
	return clampf(rounds / (full_mags * mag), 0.0, 1.0)


## Where suppressive fire goes now (a base of fire's or a "Suppress" order's point, wandering a
## little each burst), or null.
func _suppress_point() -> Variant:
	var t := _tactic()
	var kind := StringName(t.get("kind", &""))
	if kind != &"base" and kind != &"suppress":
		return null
	var aim: Vector3 = t.get("aim", Vector3.INF)
	if not aim.is_finite() or (kind == &"base" and not in_contact()):
		return null
	return aim + _suppress_jitter


## Where this unit looks when it has nothing to shoot and isn't moving: what it suppresses, or the
## sector it watches; null for neither.
func _watch_point() -> Variant:
	var t := _tactic()
	if StringName(t.get("kind", &"")) == &"watch":
		return (t.point as Vector3) + Vector3.UP * 1.2
	return _suppress_point()


## Whether the squad has thrown a screening smoke near `point` lately (SCREEN_S, SCREEN_M).
func _screened(point: Vector3) -> bool:
	return squad != null and Soldier._now() - squad.screen_at < SCREEN_S and squad.screen_point.distance_to(point) < SCREEN_M


## An ordered tactic is done: the unit holds where it got to.
func _tactic_done(t: Dictionary) -> void:
	if t.is_empty() or ordered.is_empty() or t != ordered:
		return
	ordered = {}
	if _friendly():
		order = Squad.Order.HOLD
		_hold_point = body.global_position
		_think_cd = 0.0


func _do_tactic(t: Dictionary) -> void:
	if t.is_empty():
		return
	var now := Soldier._now()
	match StringName(t.kind):
		&"maneuver":
			_tactic_maneuver(t)
		&"assault":
			var point: Vector3 = t.point
			if body.suppression >= PINNED or _flat_distance(point) <= ARRIVE + 2.0:
				_fight(point if _flat_distance(point) <= ARRIVE + 2.0 else body.global_position, 4.0)
			else:
				_go(point, true)
				bounding = true
		&"clear":
			_tactic_clear(t, now)
		&"garrison":
			var spot: Vector3 = t.spot
			if _flat_distance(spot) > ARRIVE + 0.2:
				_go(spot, true)
				return
			_has_destination = false
			if _foe() == null:
				_face(spot + (t.face as Vector3) * 5.0)
			body.want_crouch = String(t.get("port", "")) != "window" and not (_foe() != null and Soldier._now() >= _pause_until)
		&"cover":
			if not t.has("spot"):
				var found: Variant = find_cover(body.global_position, 12.0)
				t.spot = found if found != null else body.global_position
				_cover_point = t.spot
				_has_cover = found != null
			if _flat_distance(t.spot) > ARRIVE + 0.3:
				_go(t.spot, body.suppression < PINNED)
				body.want_crouch = true
			else:
				_tactic_done(t)
		&"break":
			var point: Vector3 = t.point
			if not t.has("smoked"):
				t.smoked = true
				_screen_toward_threat(point)
			if _bound_toward(point, t):
				if not ordered.is_empty():
					_tactic_done(t)
				else:
					_fight(point, 4.0)
		&"bound":
			if _bound_toward(t.point, t):
				_tactic_done(t)
		&"search":
			var point: Vector3 = t.point
			if _flat_distance(point) > ARRIVE + 0.5:
				_go(point, false)
			else:
				_has_destination = false
				_face(point + Vector3(cos(now * 0.6), 0.0, sin(now * 0.6)) * 5.0)  # looking round
		&"give_ammo":
			_tactic_give_ammo(t)
		&"pick_pack":
			_tactic_pick_pack()


## Host: "Drop packs here": the worn pack goes on the ground in front, still loaded, and this
## unit remembers where. False if it wears none (or is busy carrying someone).
func drop_pack() -> bool:
	if body.carrying != null or body.inventory.slots.get(&"backpack", &"") == &"":
		return false
	var entry := body.inventory.unequip(&"backpack")
	if entry.is_empty():
		return false
	var pos := body.global_position - body.global_basis.z * 0.6 + Vector3.UP * 0.4
	CompoundLevel.current(body).server_spawn_dropped(entry.id, 1, pos, entry.get("state", {}))
	dropped_pack = {"id": entry.id, "pos": pos}
	return true


## "Pick packs up": back to the pack it dropped, and on with it (if it's still there and no
## other pack has been put on since).
func _tactic_pick_pack() -> void:
	var pos: Vector3 = dropped_pack.get("pos", body.global_position)
	if dropped_pack.is_empty() or body.inventory.slots.get(&"backpack", &"") != &"":
		dropped_pack = {}
		ordered = {}
		return
	if _flat_distance(pos) > 1.5:
		_go(pos, true)
		return
	_has_destination = false
	var found: WorldItem = null
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := node as WorldItem
		if item and not item.is_queued_for_deletion() and item.item_id == StringName(dropped_pack.id) 				and item.global_position.distance_to(pos) < 3.0 and (found == null or item.global_position.distance_to(pos) < found.global_position.distance_to(pos)):
			found = item
	if found and body.inventory.take(found.item_id, 1, found.state) > 0:
		body.model.server_pick_up(found.global_position, found.item_id)
		GameState.item_taken(found.uid)
		found.queue_free()
	dropped_pack = {}
	ordered = {}  # back to what they were doing


## The maneuver element: along the flank route, point by point, then fighting from its end.
## Pinned, it goes to ground until it can move again.
func _tactic_maneuver(t: Dictionary) -> void:
	var route: Array = t.get("route", [])
	var leg: int = t.get("leg", 0)
	while leg < route.size() and _flat_distance(route[leg]) <= ARRIVE + 1.0:
		leg += 1
	t["leg"] = leg
	if body.suppression >= PINNED or leg >= route.size():
		_fight(route[-1] if not route.is_empty() and leg >= route.size() else body.global_position, 6.0 if leg >= route.size() else PINNED_COVER_M)
		return
	_go(route[leg], true)
	bounding = true
	if not t.get("called", false) and in_contact():
		t["called"] = true
		_call_bound()


## Clearing (SquadTactics.clear_op): to this unit's place in the stack, wait for the rest (or
## STACK_WAIT_S), then in one after the other ENTRY_GAP_S apart, each to its room corner.
func _tactic_clear(t: Dictionary, now: float) -> void:
	var op: Dictionary = t.op
	var slot: int = t.slot
	var door: Vector3 = op.entrance.door
	if not is_finite(float(op.go_at)):
		var spot: Vector3 = op.stack[slot]
		if _flat_distance(spot) > SquadTactics.STACK_READY_M:
			_go(spot, true)
			return
		_has_destination = false
		_face(door)
		op.ready[slot] = true
		op.first_ready_at = minf(float(op.first_ready_at), now)
		if (op.ready as Dictionary).size() >= int(op.units) or now - float(op.first_ready_at) >= SquadTactics.STACK_WAIT_S:
			op.go_at = now
			_callout(&"tactic", "Going in!")
		return
	if now < float(op.go_at) + slot * SquadTactics.ENTRY_GAP_S:
		_has_destination = false
		_face(door)
		return
	var corner: Vector3 = op.rooms[slot]
	if _flat_distance(corner) > ARRIVE + 0.3:
		_go(corner, true)
		return
	_has_destination = false
	op.done[slot] = true
	if not ordered.is_empty():
		if (op.done as Dictionary).size() >= int(op.units) and not bool(op.get("called", false)):
			op.called = true
			_callout(&"tactic", "Clear!")
		_tactic_done(t)


## Bounding overwatch toward `point` (t keeps the leg): in contact, legs of up to BOUND_LEG_M
## cover to cover, never while the buddy is moving (covering him instead); out of contact
## straight there. True once there.
func _bound_toward(point: Vector3, t: Dictionary) -> bool:
	if _flat_distance(point) <= ARRIVE + 0.5:
		_has_destination = false
		return true
	if not in_contact():
		t.erase("leg_point")
		_go(point, true)
		return false
	var now := Soldier._now()
	var leg: Variant = t.get("leg_point")
	if leg != null and _flat_distance(leg) <= ARRIVE + 0.4:
		t.erase("leg_point")  # made it: cover the buddy for a moment
		t["wait_until"] = now + BOUND_COVER_S
		leg = null
	if leg == null:
		if _buddy_bounding() or now < float(t.get("wait_until", 0.0)) or body.suppression >= PINNED:
			_has_destination = false
			body.want_crouch = true
			return false
		var flat := Vector3(point.x, body.global_position.y, point.z)
		var step := body.global_position.move_toward(flat, BOUND_LEG_M)
		var spot: Variant = find_cover(step, BOUND_COVER_M) if _flat_distance(point) > BOUND_LEG_M else null
		leg = spot if spot != null else (point if _flat_distance(point) <= BOUND_LEG_M \
			else NavigationServer3D.map_get_closest_point(body.get_world_3d().navigation_map, step))
		t["leg_point"] = leg
		_call_bound()
	_go(leg, true)
	bounding = true
	return false


## Breaking contact toward `point`: smoke between this unit and the threat first, over open
## ground in contact, unless the squad screened there lately.
func _screen_toward_threat(point: Vector3) -> void:
	if not in_contact() or _flat_distance(point) <= SMOKE_OPEN_M or _screened(body.global_position):
		return
	var to := body.threat_pos - body.global_position
	to.y = 0.0
	if to.length() > SCREEN_RANGE_M or to.length() < 1.0:
		return
	var at := body.global_position + to.normalized() * minf(SMOKE_OUT_M, to.length() * 0.5)
	if _throw(&"smoke_grenade", at) and squad:
		squad.screen_at = Soldier._now()
		squad.screen_point = at


## "Give me ammo": to the asker, then magazines of their ammunition (GIVE_MAGS) if this unit
## carries any; done either way.
func _tactic_give_ammo(t: Dictionary) -> void:
	var who := t.get("who") as Soldier
	if who == null or not is_instance_valid(who) or not who.vitals.is_up():
		_tactic_done(t)
		return
	if _flat_distance(who.global_position) > GIVE_M:
		_go(who.global_position, true)
		return
	_has_destination = false
	_face(who.global_position)
	var ammo := StringName(t.get("ammo", &""))
	var given := 0
	var full := false
	for i in GIVE_MAGS:
		var entry := _take_out(ammo)
		if entry.is_empty():
			break
		if who.inventory.take(entry.id, 1, entry.get("state", {})) == 0:
			body.inventory.take(entry.id, 1, entry.get("state", {}))  # no room on them: keep it
			full = true
			break
		given += 1
	print("[tactics] %s brings %s %d x %s (%s)" % [body.name, who.name, given, ammo, "no room" if full else ("none left" if given == 0 else "handed over")])
	if given > 0:
		_callout(&"tactic", "Ammo!")
		if not who.is_ai():
			who._client_message.rpc_id(who.owner_peer(), "%s gave you %d magazine%s" % [body.display_name(), given, "s" if given > 1 else ""])
	elif not who.is_ai():
		who._client_message.rpc_id(who.owner_peer(), "No room for more magazines" if full else "%s has none to spare" % body.display_name())
	ordered = {}  # back to what they were doing


## Host: one stowed unit of `id` taken out of this unit's containers ({"id", "count", "state"}),
## or {} if it carries none.
func _take_out(id: StringName) -> Dictionary:
	if id == &"":
		return {}
	for container in body.inventory.search_containers():
		var list: Array = body.inventory.containers[container]
		for i in list.size():
			if list[i].id == id:
				return body.inventory.remove_entry(container, i, 1)
	return {}


func _tactic_text() -> String:
	var t := _tactic()
	match StringName(t.get("kind", &"")):
		&"maneuver":
			return "Flanking"
		&"assault":
			return "Assaulting"
		&"clear":
			return "Clearing" if is_finite(float(t.op.go_at)) else "Stacking up"
		&"garrison":
			return "Holding a %s" % String(t.get("port", "position")) if _flat_distance(t.spot) <= ARRIVE + 0.2 else "Taking a position"
		&"cover":
			return "Taking cover"
		&"break":
			return "Breaking contact"
		&"bound":
			return "Bounding"
		&"search":
			return "Searching"
		&"give_ammo":
			return "Bringing ammo"
		&"pick_pack":
			return "Getting the pack"
	return "Following"


# --- Perception -----------------------------------------------------------

func _find_target() -> Soldier:
	if body.stunned_s > 0.0:
		return null
	if focus != null and (not is_instance_valid(focus) or focus.is_queued_for_deletion() or not focus.vitals.is_up()):
		focus = null  # the target is down: pick freely again
	if focus != null and focus.faction != body.faction and not Person.is_noncombatant(focus) \
			and body.global_position.distance_to(focus.global_position) <= Squad.TARGET_RANGE and can_see(focus):
		return focus
	var best: Soldier = null
	var best_dist := SQUAD_SIGHT_RANGE if _friendly() else SIGHT_RANGE
	var check: Soldier = null
	var check_dist := DEAD_CHECK_M
	var clearing := _clearing()
	var seen := {}
	var suspect_a := 0.0
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s.faction == body.faction or s.vitals.is_dead() or s.is_queued_for_deletion():
			continue
		if Person.is_noncombatant(s):
			continue  # civilians, HVTs and hostiles who gave up are never targets (people, wave 4)
		var d := body.global_position.distance_to(s.global_position)
		if not s.vitals.is_up():
			# Unconscious foes are left alone, except for a dead-check while clearing.
			if clearing and d < check_dist and can_see(s):
				check = s
				check_dist = d
			continue
		var steps := Spotting.footsteps_m(s)
		var leaves := INF  # metres of foliage in the way; INF: not in sight at all
		if (d <= steps or d < best_dist) and can_see(s):
			leaves = Spotting.foliage_m(_zone_scatter(), body, s)
		var in_sight := leaves < Spotting.FOLIAGE_OPAQUE_M  # deep in the leaves: lost, awareness fades
		if d <= steps and not in_sight:
			seen[s.get_instance_id()] = true  # heard, not seen: keeps awareness from fading
			hear(s, s.global_position, Spotting.HEARD_STEPS_PER_S * SCAN_S)
			continue
		if d < best_dist and in_sight:
			seen[s.get_instance_id()] = true
			var a := _build_awareness(s, leaves)
			if a >= 1.0:
				best = s
				best_dist = d
			elif a >= Spotting.SUSPECT and a > suspect_a:
				suspect_a = a
				_suspect_pos = s.global_position
				_suspect_at = Soldier._now()
	_fade_awareness(seen)
	# A dead-check, once started, goes on until the body is dead or out of range, even after
	# the advance ends; only new ones need clearing.
	if check != null:
		_dead_check = check
	elif _dead_check != null and not _dead_check_valid(_dead_check):
		_dead_check = null
	return best if best != null else _dead_check


## One scan's worth of spotting `s` (in sight, `leaves` metres of foliage in the way):
## awareness rises by SCAN_S over the time Spotting gives. Returns the new awareness.
func _build_awareness(s: Soldier, leaves := 0.0) -> float:
	var id := s.get_instance_id()
	var a: float = _aware.get(id, 0.0)
	if a < 1.0:
		if _preset == "":
			_preset = Spotting.preset_of(body)
		var suppressed := body.suppression >= SUPPRESSED
		var t := Spotting.spot_seconds(body, s, _preset, combat, suppressed, Soldier._now(), leaves, not in_contact() and not suppressed)
		a = 1.0 if t <= SCAN_S * 0.5 else minf(a + SCAN_S / t, 1.0)
		_aware[id] = a
	return a


## The scrub and trees of this body's zone (null off a zone), looked up once.
func _zone_scatter() -> ZoneScatter:
	if not _scatter_found:
		_scatter_found = true
		_scatter = Spotting.scatter_of(body)
	return _scatter


## Awareness of those out of sight this scan fades over Spotting.FADE_S.
func _fade_awareness(seen: Dictionary) -> void:
	for id: int in _aware.keys():
		if seen.has(id):
			continue
		var a: float = _aware[id] - SCAN_S / Spotting.FADE_S
		if a <= 0.0:
			_aware.erase(id)
		else:
			_aware[id] = a


## Someone was partly spotted in the last SUSPECT_S.
func suspecting() -> bool:
	return Soldier._now() - _suspect_at < SUSPECT_S


## Still worth dead-checking: unconscious (not dead) and within DEAD_CHECK_M. Kept while it
## drops in and out of sight behind low cover: only death or distance ends it.
func _dead_check_valid(s: Soldier) -> bool:
	return is_instance_valid(s) and not s.is_queued_for_deletion() and not s.vitals.is_dead() and not s.vitals.is_up() \
		and body.global_position.distance_to(s.global_position) <= DEAD_CHECK_M


## Clearing or assaulting through a position (pushing toward the enemy, searching, or moving
## on an order while in contact): when unconscious foes nearby get dead-checked.
func _clearing() -> bool:
	return _advancing or intent == Intent.INVESTIGATE or (intent == Intent.MOVE_TO and in_contact())


func can_see(other: Soldier) -> bool:
	var from := body.camera.global_position
	var to := other.aim_point()  # follows stance: crouched and prone targets sit lower
	if SmokeCloud.blocks(from, to):
		return false
	return Throwables.clear_line(body.get_world_3d(), from, to)


# --- Cover ----------------------------------------------------------------

## Best spot on the navmesh near `anchor` that the threat can't hit, preferring spots you
## can shoot back from.
func find_cover(anchor: Vector3, leash: float) -> Variant:
	var map := body.get_world_3d().navigation_map
	var world := body.get_world_3d()
	var best: Variant = null
	var best_score := INF
	for ring in COVER_RINGS:
		if ring > leash + 0.1:
			break
		for k in 12:
			var angle := TAU * k / 12.0 + ring
			var p := anchor + Vector3(cos(angle), 0.0, sin(angle)) * ring
			var q := NavigationServer3D.map_get_closest_point(map, p)
			if Vector2(q.x - p.x, q.z - p.z).length() > 0.6 or not _cover_protects(q) or _cover_taken(q):
				continue
			var score := _flat_distance(q) + q.distance_to(anchor) * 0.5
			if not VoxelWorld.stops_round_in(body, body.threat_pos + Vector3.UP * 1.5, q + Vector3.UP * 0.9, SOFT_COVER_TEST_J):
				score += SOFT_COVER_PENALTY  # only wood or sheet metal in the way: rounds come through
			if Throwables.clear_line(world, q + Vector3.UP * 1.6, body.threat_pos + Vector3.UP * 1.2):
				score -= 3.0  # low cover: you can stand up and return fire
			score += maxf(0.0, 6.0 - q.distance_to(body.threat_pos)) * 2.0
			if score < best_score:
				best = q
				best_score = score
	return best


func _cover_protects(point: Vector3) -> bool:
	return not Throwables.clear_line(body.get_world_3d(), body.threat_pos + Vector3.UP * 1.5, point + Vector3.UP * 0.9)


func _cover_taken(point: Vector3) -> bool:
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var other := SquadAI.of(n)
		if other and other != self and other._has_cover and other._cover_point.distance_to(point) < 1.2:
			return true
	return false


func _at_cover() -> bool:
	return _has_cover and _flat_distance(_cover_point) <= ARRIVE + 0.4


func _buddy_bounding() -> bool:
	var ai := SquadAI.of(buddy) if is_instance_valid(buddy) and buddy.vitals.is_up() else null
	return ai != null and ai.bounding


# --- Shooting -------------------------------------------------------------

func _shoot() -> void:
	if LauncherAI.think(self):
		return  # the launcher has them: vehicles, a group behind cover, an order (wave 5)
	var now := Soldier._now()
	var weapon := body.active_weapon()
	if weapon == null or weapon.type != "weapon" or body.carrying != null or body.is_reloading \
			or body.stunned_s > 0.0 or (body.suppression >= PINNED and not _suppressing) or not weapons_free():
		return
	var foe := _foe()
	var aim_at: Variant = null
	if foe != null:
		aim_at = foe.aim_point()
	elif _suppressing:
		aim_at = body.threat_pos + Vector3.UP * 1.0  # keep their heads down before going out to the casualty
	elif _suppress_point() != null:
		aim_at = _suppress_point()
	elif intent != Intent.CASUALTY and (_buddy_bounding() or _cover_medic) and in_contact() and now - _last_contact < 5.0:
		aim_at = body.threat_pos + Vector3.UP * 1.0  # covering fire while the buddy (or a medic) moves
	elif intent == Intent.FIGHT:
		_maybe_frag()
	if aim_at == null:
		return
	var error := _aim_at(aim_at)
	if body.want_crouch and _at_cover() and foe != null:
		body.want_crouch = false  # stand up to shoot over cover
		return
	if error > deg_to_rad(6.0) or now < _next_shot or now < _pause_until or now < body._busy_until:
		return
	if body.inventory.rounds_in(body.active_slot) <= 0 or _friendly_in_line(aim_at):
		return
	var auto: bool = weapon.stats.get("auto", false)
	_next_shot = now + 60.0 / float(weapon.stats.get("rpm", 600)) * (1.0 if auto else 1.6)
	if _burst_left <= 0:
		_burst_left = randi_range(3, 5) if auto else randi_range(2, 3)
		_suppress_jitter = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.5), randf_range(-1, 1)) * SUPPRESS_SPREAD_M
	_burst_left -= 1
	if _burst_left <= 0:
		_pause_until = now + randf_range(0.5, 1.1) / lerpf(0.7, 1.3, combat)
	var dir := body._spread_direction(weapon)
	var extra := deg_to_rad(_aim_error_deg(foe != null))
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * tan(extra) * 0.6).normalized()
	body._server_fire.rpc_id(1, body.camera.global_position, dir, body.active_slot)


## The aim error (degrees) this unit adds to its weapon's own spread: less skill, suppression,
## firing at a point rather than a seen foe, and shaken morale all widen it.
func _aim_error_deg(seen_foe: bool) -> float:
	var shaken := maxf(MORALE_SHAKEN - morale, 0.0) / MORALE_SHAKEN  # 0 steady .. 1 no morale left
	return (1.0 - combat) * 2.0 + body.suppression * 4.0 + (0.0 if seen_foe else 3.0) + shaken * MORALE_SHAKEN_AIM_DEG


## The half-angle (radians) this unit's next rounds may stray by: the weapon's spread plus
## its aim error (_aim_error_deg).
func _fire_cone() -> float:
	var weapon := body.active_weapon()
	var spread := float(weapon.stats.get("spread_deg", 1.0)) if weapon else 1.0
	return deg_to_rad(spread + _aim_error_deg(_foe() != null))


## Turns the body and head toward a point; returns the remaining angle in radians.
func _aim_at(point: Vector3) -> float:
	var from := body.camera.global_position
	var d := point - from
	var flat := Vector2(d.x, d.z)
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, flat.length())
	var step := 1.0 - exp(-TURN_RATE * lerpf(0.6, 1.4, combat) * get_physics_process_delta_time())
	body.rotation.y = lerp_angle(body.rotation.y, yaw, step)
	body.head.rotation.x = lerpf(body.head.rotation.x, clampf(pitch, -1.4, 1.4), step)
	return (-body.camera.global_basis.z).angle_to(d.normalized())


## Fire discipline (queue 17 part 5): true if someone this unit must not hit (_protects), up
## or down, is in the line of fire to `point` or within DOWNRANGE_M past it, closer to the line
## than FRIENDLY_CLEARANCE plus what the rounds' cone (`cone`, radians; _fire_cone() when
## negative) has spread to by them. Upright people count from shins to head, prone or downed
## ones around their chest, LYING_EXTRA_M wider.
func _friendly_in_line(point: Vector3, cone := -1.0) -> bool:
	var from := body.camera.global_position
	var reach := from.distance_to(point)
	if reach < 0.01:
		return false
	var ahead := (point - from) / reach
	var far := point + ahead * DOWNRANGE_M
	var widen := tan(_fire_cone() if cone < 0.0 else cone)
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if not _protects(s):
			continue
		var lying := _lying(s)
		var low := s.aim_point() if lying else s.global_position + Vector3.UP * 0.3
		var high := low if lying else s.global_position + Vector3.UP * (1.2 if s.is_crouching() else 1.7)
		var closest := Geometry3D.get_closest_points_between_segments(from, far, low, high)
		var along := (closest[0] - from).dot(ahead)
		if along < MUZZLE_M:
			continue  # beside or behind the muzzle
		var clearance := FRIENDLY_CLEARANCE + along * widen + (LYING_EXTRA_M if lying else 0.0)
		if closest[0].distance_to(closest[1]) < clearance:
			return true
	return false


## Someone this unit must not hurt: alive, not itself, on its side, or a civilian, HVT or
## captive (Person.is_noncombatant; people, wave 4).
func _protects(s: Soldier) -> bool:
	return s != null and s != body and not s.is_queued_for_deletion() and not s.vitals.is_dead() \
		and (s.faction == body.faction or Person.is_noncombatant(s))


## Lying on the ground: prone, or down (where the ragdoll lies, Soldier.aim_point).
static func _lying(s: Soldier) -> bool:
	return not s.vitals.is_up() or s.movement.is_prone()


## Grenade discipline (queue 17 part 5): a frag thrown from `from` at `at` hurts nobody this
## unit protects: none within FRAG_RADIUS + FRAG_SAFETY_M of where it lands, none within
## LOB_FRIEND_M of its arc.
func _frag_safe(from: Vector3, at: Vector3) -> bool:
	var arc := _lob_points(from, at)
	var ahead := Vector3(at.x - from.x, 0.0, at.z - from.z).normalized()
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if not _protects(s):
			continue
		var p := s.aim_point() if _lying(s) else s.global_position
		if p.distance_to(at) < Throwables.FRAG_RADIUS + FRAG_SAFETY_M:
			return false
		var low := p if _lying(s) else s.global_position + Vector3.UP * 0.3
		var high := p if _lying(s) else s.global_position + Vector3.UP * 1.8
		for i in range(1, arc.size()):
			var closest := Geometry3D.get_closest_points_between_segments(arc[i - 1], arc[i], low, high)
			if (closest[0] - from).dot(ahead) >= MUZZLE_M and closest[0].distance_to(closest[1]) < LOB_FRIEND_M:
				return false  # (someone beside the thrower's hand isn't under the arc)
	return true


func _maybe_frag() -> void:
	if _grenade_cd > 0.0 or _no_los_s < 4.0 or not in_contact():
		return
	var d := body.global_position.distance_to(body.threat_pos)
	if d < 8.0 or d > 25.0:
		return
	var from := body.camera.global_position + Vector3.UP * 0.2
	if not _frag_safe(from, body.threat_pos):
		return  # friendlies (or civilians, people wave 4) near the blast or under the arc
	if not _lob_clear(from, body.threat_pos):
		return  # it would hit a wall or roof on the way and bounce back
	var now := Soldier._now()
	if squad and now - squad.frag_at < SQUAD_FRAG_GAP_S and squad.frag_point.distance_to(body.threat_pos) < SQUAD_FRAG_SPREAD_M:
		return  # a squadmate just threw one there: the whole squad dumped frags on one spot (roles, R0203)
	_grenade_cd = GRENADE_COOLDOWN_S
	if squad:
		squad.frag_at = now
		squad.frag_point = body.threat_pos
	_throw(&"frag_grenade", body.threat_pos)


## Whether a grenade lobbed from `from` (Throwables.lob_velocity) flies to `at` without
## hitting anything on the way: a frag that clips a wall or a roof lands among your own.
func _lob_clear(from: Vector3, at: Vector3) -> bool:
	var world := body.get_world_3d()
	var arc := _lob_points(from, at)
	for i in range(1, arc.size()):
		if not Throwables.clear_line(world, arc[i - 1], arc[i]):
			return false
	return true


## Points along a grenade's arc lobbed from `from` at `at` (Throwables.lob_velocity), from the
## hand to just short of the landing (the last tenth comes down onto the target).
static func _lob_points(from: Vector3, at: Vector3) -> PackedVector3Array:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var velocity := Throwables.lob_velocity(from, at)
	var flight := clampf(from.distance_to(at) / 12.0, 0.6, 1.6)  # as lob_velocity times it
	var out := PackedVector3Array([from])
	for i in range(1, LOB_CHECKS + 1):
		var t := flight * 0.9 * i / LOB_CHECKS
		out.append(from + velocity * t + Vector3.DOWN * 0.5 * gravity * t * t)
	return out


func _throw(id: StringName, at: Vector3) -> bool:
	if Soldier._now() < body._busy_until or not body.inventory.remove_one(id):
		return false
	body._busy_until = Soldier._now() + Soldier.THROW_BUSY_S
	var from := body.camera.global_position + Vector3.UP * 0.2
	CompoundLevel.current(body).server_throw(id, from, Throwables.lob_velocity(from, at), body)
	if Callouts.THROW_IDS.has(id):
		_callout(Callouts.THROW_IDS[id])
	return true


# --- Callouts -------------------------------------------------------------

func _callout(id: StringName, text := "") -> void:
	var callouts := Callouts.of(body)
	if callouts:
		callouts.say(body, id, text)


## Bounding in contact: "Moving!", and the battle buddy answers "Covering!".
func _call_bound() -> void:
	_callout(&"moving")
	var mate := buddy
	var mate_ai := SquadAI.of(mate) if is_instance_valid(mate) and mate.vitals.is_up() else null
	if mate_ai and not mate_ai.bounding:
		mate_ai._callout(&"covering")


# --- Steering -------------------------------------------------------------

func _go(point: Vector3, run := false) -> void:
	_destination = point
	_has_destination = true
	_run = run or _flat_distance(point) > RUN_DISTANCE


## Follows a navmesh path to the destination, judging waypoints by flat distance (the
## baked mesh sits a little above the ground, so 3D distances never quite close).
func _steer(delta: float) -> void:
	var dir := Vector3.ZERO
	_repath_cd -= delta
	if _has_destination and _flat_distance(_destination) > ARRIVE and body.stunned_s <= 0.0:
		if _repath_cd <= 0.0 or _path_target.distance_to(_destination) > 0.5:
			_repath_cd = REPATH_S
			_path_target = _destination
			_path = NavigationServer3D.map_get_path(body.get_world_3d().navigation_map, body.global_position, _destination, true)
			_path_index = 0
		while _path_index < _path.size() and _flat_distance(_path[_path_index]) < WAYPOINT_REACH:
			_path_index += 1
		var next := _path[_path_index] if _path_index < _path.size() else _destination
		dir = next - body.global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.05 else Vector3.ZERO
	var local := body.global_basis.inverse() * dir
	body.move_input = Vector2(local.x, local.z)
	var foe := _foe()
	body.want_sprint = _run and not body.want_crouch and foe == null and _may_sprint()
	if foe == null and dir != Vector3.ZERO and body.carrying == null:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-TURN_RATE * get_physics_process_delta_time()))
		body.head.rotation.x = lerpf(body.head.rotation.x, 0.0, 0.1)
	elif foe == null and dir == Vector3.ZERO and _watch_point() != null and intent != Intent.CASUALTY:
		_aim_at(_watch_point())  # suppressing, or watching a sector
	elif foe == null and dir == Vector3.ZERO and in_contact() and not (intent == Intent.CASUALTY and care == Care.TREAT):
		_aim_at(body.threat_pos + Vector3.UP * 1.2)
	elif foe == null and dir == Vector3.ZERO and suspecting() and intent != Intent.CASUALTY:
		_aim_at(_suspect_pos + Vector3.UP * 1.0)  # something there: look (Spotting)


## Safe units only run to catch up from far behind; Stealth units never sprint.
func _may_sprint() -> bool:
	match combat_mode:
		Squad.CombatMode.SAFE:
			return fighting() or _flat_distance(_destination) > SAFE_CATCH_UP_M
		Squad.CombatMode.STEALTH:
			return false
	return true


func _stop() -> void:
	_has_destination = false
	body.move_input = Vector2.ZERO
	body.want_sprint = false
	body.want_aim = false


# --- Helpers --------------------------------------------------------------

static func _flat_between(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _flat_distance(point: Vector3) -> float:
	return Vector2(body.global_position.x - point.x, body.global_position.z - point.z).length()



static func _mag_size(weapon: ItemData) -> int:
	if weapon == null:
		return 0
	var ammo := Soldier._ammo_of(weapon)
	return ItemDB.get_item(ammo).magazine_rounds() if ItemDB.has_item(ammo) else 0


func _name_of(s: Soldier) -> String:
	if s == null or not is_instance_valid(s):
		return "them"
	return "the lead" if squad and s == squad.leader else s.display_name()
