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
##   under fire (stopped, and prone if he's out in the open), and does the rest (bandages,
##   seals, splints, morphine) out of contact or in cover. What it can't fix itself, it calls
##   "Medic!" for, once its own tourniquet is on; a squadmate who comes meanwhile sees to the
##   other wounds and never holds up his own tourniquet. A medic doesn't use on itself an item
##   nobody else on its side carries (massive bleeding aside).
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
## "give_ammo" (to "who", hands over magazines), "pick_pack" (back for the pack it dropped),
## "exo_in" (to the HX-1 "uid" and into it). An ordered one that ends (cover, break, bound,
## clear, give_ammo) leaves the unit holding where it got to; a timed one ("until") just ends.
## "Climb into the HX-1": he stands this far behind the suit's feet at its release, and steps
## onto that spot from this close (nav stops short of a suit's bulk).
const EXO_STAND_M := 0.75
const EXO_SNAP_M := 2.5
const MOVING_TACTICS: Array[StringName] = [&"maneuver", &"assault", &"clear", &"garrison", &"cover", &"break", &"bound", &"search", &"give_ammo", &"pick_pack", &"exo_in", &"climb"]
## Climb order (Squad.order_climb): up there once its feet are within CLIMB_UP_M below the
## spot and CLIMB_DONE_M of it; at the wall (CLIMB_AT_WALL_M of the spot) with no ledge it
## can climb for CLIMB_GIVE_UP_S, the order ends where it stands.
const CLIMB_UP_M := 0.6
const CLIMB_DONE_M := 1.5
const CLIMB_AT_WALL_M := 2.5
const CLIMB_GIVE_UP_S := 3.0
## How long "Suppress" lasts (Squad.order_suppress).
const SUPPRESS_ORDER_S := 20.0
## Who decides what a unit does (Captain, 2026-10-17: "Player orders -> squad tactics -> buddy
## team tactics -> indiv tactics"; B team "not responding" was its own fighting and casualty care
## outscoring a player's orders):
## - a player's order: an ordered tactic (ORDERED_SCORE) or a move or hold (PLAYER_ORDER_SCORE)
##   comes first, below only survival reflexes (an empty magazine, its own bleeding). A move
##   order rules until it gets there; a hold keeps fighting from its spot (HOLD's act fights)
##   and still treats casualties near the spot (HOLD_CARE_M);
## - the squad's own tactics next (TACTIC_SCORE: an evaluator task, by fire team or buddy pair,
##   Tactics.elements);
## - then the unit's own: going to a casualty (in contact CASUALTY_CONTACT_SCORE: above fighting
##   where it stands, 0.7, by more than HYSTERESIS so a medic who's shooting does break off; out
##   of contact 0.9), only when the rescue is covered (_rescue_hot: smoke, covering fire, or the
##   shooter pinned), then fighting where it stands.
const TACTIC_SCORE := 0.75
const ORDERED_SCORE := 0.93
const PLAYER_ORDER_SCORE := 0.93
const CASUALTY_CONTACT_SCORE := 0.82
## Captain, 2026-10-17: "enemy medics are still medicing under fire, and the new teams even come in
## and start aid on downed enemy teams instead of focusing on player teams". The enemy fights
## first: in contact its casualty care scores HOSTILE_CARE_CONTACT_SCORE, under fighting (0.7),
## and it leaves a casualty it was treating when fire comes in; within HOSTILE_CARE_HOT_S of
## contact it only sees to its own squad's casualties (an arriving team fights, not nurses).
const HOSTILE_CARE_CONTACT_SCORE := 0.6
const HOSTILE_CARE_HOT_S := 30.0
## Captain, same night: "medics should focus on combat casualty care but only where they can". An
## enemy medic, not pinned, scores care above fighting in contact (HOSTILE_MEDIC_CONTACT_SCORE;
## _find_casualty already skips a casualty the squad's fire covers: _rescue_hot) and also sees
## to other teams' casualties within HOSTILE_MEDIC_REACH_M while it's hot.
const HOSTILE_MEDIC_CONTACT_SCORE := 0.85
const HOSTILE_MEDIC_REACH_M := 25.0
const HOLD_CARE_M := 12.0
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
## Aim error (degrees) at combat skill 0, falling to none at 1 (was 2.0: at the longer ranges a
## middling shooter put every round metres off).
const AIM_UNSKILLED_DEG := 1.2
## Falling back: this far from the threat (or toward the leader), into cover within FALL_BACK_COVER_M.
const FALL_BACK_M := 20.0
const FALL_BACK_COVER_M := 8.0
## Hostiles see this far (Captain, 2026-10-13: engagement ranges up; was 60 m). Doctrine's
## engage_m fits it (insurgents 180 m, regulars 200 m) and Doctrine.engage_m never goes past
## it (audit F-03; still pending, A3-07).
const SIGHT_RANGE := 300.0  # (was 200; Captain, 2026-10-17: they "don't engage far enough out")
const SUPPRESSED := 0.5
const PINNED := 0.85
const HYSTERESIS := 0.1
const ARRIVE := 0.7
## Digging in (dig phase 4, Captain 2026-10-19: "AI dig in", and "they dont bore down when they
## build cover in front of them"): a friendly soldier holding a spot, out of contact, for
## DIG_IN_AFTER_S builds cover in front of it (Digging.COVER) up to AI_COVER_TO_M (kneeling
## height), facing where the threat last came from. Contact stops it. Proposed.
const DIG_IN_AFTER_S := 12.0
const AI_COVER_TO_M := 0.75
const RUN_DISTANCE := 5.0
const WAYPOINT_REACH := 0.45
## Points more than this above or below a unit are on another floor (F-01): distances to them
## are measured in 3D, so a corner upstairs is never "reached" from the room under it.
const FLOOR_DY_M := 1.6
const REPATH_S := 1.0
const COVER_RINGS: Array[float] = [2.0, 4.0, 6.0, 8.0, 10.0]
const COVER_SEARCH_S := 1.0
## Proposed (Captain, 2026-10-14: they bunched up): no two take cover, or a halt spot, within
## COVER_GAP_M of each other (was 1.2 m: the same rock); a long wall still takes several.
const COVER_GAP_M := 2.5
## Proposed (Captain, 2026-10-14): keeping apart while following or fighting in formation. A
## squadmate moving steers off anyone within SEPARATION_M (more the closer); one standing still
## steps away from anyone within STACK_M (squadmates pass through each other, so nothing else
## stops two standing in one spot). Not while boarding, at a casualty, in a stack or a room.
const SEPARATION_M := 3.0
## A unit keeps its crouch (or stands) at least this long before changing again, unless pinned
## or stunned (down at once). Captain, 2026-10-15: squadmates bounced up and down; a follower
## crouched each time he reached his moving slot and stood to catch up, and a base of fire
## stood for every burst and crouched in every pause.
const CROUCH_HOLD_S := 1.2
## Back down from standing only after this long (Captain, 2026-10-17: "fix ai crouch bouncing
## still": at cover it stood for each burst and ducked between them, CROUCH_HOLD_S being barely
## longer than the 0.5-1.1 s pause, so it bobbed every second in a firefight). Pinned or stunned
## still goes down at once.
const CROUCH_DOWN_HOLD_S := 2.5
const STACK_M := 1.5
## Cover that only hides you (wood or sheet metal a rifle round goes through, see
## VoxelWorld.MATERIALS) scores this much worse than cover that stops a round arriving with
## SOFT_COVER_TEST_J (an M855 at close range), so AI picks concrete when it has the choice.
const SOFT_COVER_PENALTY := 6.0
## How much better low cover you can shoot over scores in find_cover (it's the most a candidate's
## score can drop, so a candidate already this much worse than the best is skipped unchecked).
const COVER_LOW_BONUS := 3.0
const SOFT_COVER_TEST_J := 1650.0
## A hostile out of sight of the enemy this long pushes one bound toward where it was seen, to
## cover (Captain, 2026-10-17: "enemies also feed the meat grinder too much... they need to be
## capable fighters, not cattle that run around and die"; was 6 s, into the open): only to a
## covered spot within ADVANCE_COVER_M of the bound's end, and only while its morale holds
## (ADVANCE_MORALE: losses and suppression nearby hold it back; Captain: firefights "end
## really fast").
const ADVANCE_AFTER_S := 15.0
const ADVANCE_STEP := 8.0
const ADVANCE_COVER_M := 6.0
const ADVANCE_MORALE := 0.6
const WORLD_MASK := 1
## Line of fire (Captain, v0.4.6 playtest: "friendlies shoot at and try to shoot through walls,
## enemies too"): no round leaves unless it would get there (_fire_line). Fire at a point
## (suppression, covering fire) may be stopped by the world up to FIRE_LINE_SLACK_M short of
## the point (the cover the enemy hides behind is a fair mark; a wall in front of the shooter
## isn't); fire at a foe, up to FIRE_LINE_FOE_SLACK_M short of him. A round that would go
## through what's in the way (wood, sheet metal: VoxelWorld.stops_round_in, with the round's
## energy at that range) counts as getting there; concrete and brick never let it. The check
## is kept FIRE_LINE_CACHE_S (one ray or so a burst, not one a frame).
const FIRE_LINE_SLACK_M := 4.5
const FIRE_LINE_FOE_SLACK_M := 0.5
const FIRE_LINE_CACHE_S := 0.3
## Eye heights a fire position is judged from (SoldierMovement's crouched and standing heads).
const FIRE_EYE_CROUCH_M := 1.0
const FIRE_EYE_STAND_M := 1.6
## A base of fire or a "Suppress" order with no line of fire for NO_SHOT_MOVE_S looks for a fire
## position (_find_fire_spot): a navmesh spot on FIRE_SPOT_RINGS round him (a path no longer than
## FIRE_SPOT_PATH_M) with a line to the aim from a crouch or on his feet, the shortest move
## first, in cover from the aim if it can, nobody else's. None: he holds, says "No shot!" and
## looks again FIRE_SPOT_RETRY_S later.
const NO_SHOT_MOVE_S := 2.5
const FIRE_SPOT_RINGS: Array[float] = [2.0, 4.0, 6.0, 8.0, 10.0, 12.5, 15.0, 18.0]
const FIRE_SPOT_PATH_M := 26.0
const FIRE_SPOT_RETRY_S := 6.0
## A fire position goes with its aim: the aim moving this far means looking again.
const FIRE_SPOT_AIM_M := 4.0
## What _fire_line_state found: a clear line, one clear only from his feet (he is crouched), none.
enum FireLine { CLEAR, STAND, BLOCKED }
const TURN_RATE := 7.0
## Proposed (Captain, P0362: close-range hostiles were lasers): how fast the aim can swing
## (degrees a second) at combat skill 0 and 1. Below this _aim_at turns as it always did; a
## big swing (a target behind him) takes its time. Pitch swings at PITCH_SWING_MULT of that.
const SWING_UNSKILLED_DEG_S := 150.0
const SWING_SKILLED_DEG_S := 400.0
const PITCH_SWING_MULT := 0.6
## Proposed: a target more than TURN_HOLD_MIN_DEG off his aim freezes him this long before he
## starts to turn (taking in what he saw), skill 0 and 1.
const TURN_HOLD_UNSKILLED_S := 0.35
const TURN_HOLD_SKILLED_S := 0.1
const TURN_HOLD_MIN_DEG := 20.0
## Proposed: close-range aim (_cqb_aim_point). Within CQB_FULL_M the full model applies,
## fading out to none at CQB_FADE_M (the range hold, RANGE_HOLD_*, takes over). The first
## shots land up to CQB_ACQ_*_M off the chest (mostly low: the muzzle comes up onto him; high in
## CQB_HIGH_SHARE of acquisitions, at CQB_HIGH_MULT of the size: a snap from above, the few
## rounds that go to the neck or head), settling over CQB_SETTLE_*_S once the reaction time
## has passed; each burst holds a small offset of its own (CQB_BURST_OFFSET_M, one sigma).
## Skill 0 and 1.
const CQB_FULL_M := 10.0
const CQB_FADE_M := 30.0
const CQB_ACQ_UNSKILLED_M := 0.45
const CQB_ACQ_SKILLED_M := 0.12
const CQB_HIGH_SHARE := 0.15
const CQB_HIGH_MULT := 0.6
const CQB_SETTLE_UNSKILLED_S := 0.6
const CQB_SETTLE_SKILLED_S := 0.25
const CQB_BURST_OFFSET_M := 0.05
## Proposed (Captain, P0362: the old gate fired once the turn was within 6 degrees, which at
## 2-6 m is 20-60 cm, and the sights came down onto a man from eye level through his head and
## neck): a round at a seen foe goes only once the sights are within GATE_*_M (skill 0 and 1)
## of the aim point, measured at his range; on the high side only GATE_HIGH_MULT of that (a
## high miss is a head shot), on the low side GATE_LOW_MULT (a low one is still his belly). Out
## at range never tighter than GATE_MIN_DEG, so he still fires at a man on the move.
const GATE_UNSKILLED_M := 0.25
const GATE_SKILLED_M := 0.15
const GATE_HIGH_MULT := 0.5
const GATE_LOW_MULT := 1.5
const GATE_MIN_DEG := 0.3
## Proposed (Captain, P0362: one guard downed three at 155 m in 13 s): beyond close range each
## burst is held a little off (one sigma RANGE_HOLD_*_DEG, skill 0 and 1: the whole burst
## groups round a wrong point, as a man's hold on a small far figure wanders), fully from
## CQB_FADE_M out. The first bursts at a new target are wider (RANGE_ACQ_MULT more, settling
## over RANGE_SETTLE_S: finding the range, the wind, his own fall of shot).
const RANGE_HOLD_UNSKILLED_DEG := 0.35
const RANGE_HOLD_SKILLED_DEG := 0.1
const RANGE_ACQ_MULT := 1.0
const RANGE_SETTLE_S := 4.0
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
## Ammo bearer (new role, CLAUDE.md squad-roles-pmc bundle): close enough to hand belt boxes
## across, and how often it checks (mirrors MEDIC_FAR_M/MEDIC_CALL_S for ammunition instead of
## care). A bearer doesn't go looking for its gunner yet (first slice): it tops him up whenever
## squad movement already has them this close, the way any buddy pair closes up on its own.
const AMMO_RESUPPLY_M := 3.0
const AMMO_RESUPPLY_COOLDOWN_S := 4.0
## A gunner below this many spare belt boxes stowed is worth topping up.
const GUNNER_LOW_BELTS := 1
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
## A body laid at the lay spot lies within LAID_M of it, measured to where it lies
## (Soldier.body_point): the bearer lowers it once within 1 m of the spot, 0.8 m in front of
## him (Soldier._put_down_spot), and its ragdoll's chest settles some 1.3 m from the capsule.
## Measured against LAY_NEAR_M alone it often read as not there (2.2-2.6 m), and the bearer
## lifted the casualty again to bring him closer, over and over (casualty R0123-R0125).
const LAID_M := LAY_NEAR_M + 1.5
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
## Captain, 2026-10-14: no reflex body-hauling ("they can if they choose to. bots should act
## like players, communicate with the player"). A squadmate recovers a fallen friendly's body
## only once out of contact BODY_QUIET_S, hands free and with nothing ordered, and only with
## somewhere to take it within BODY_TAKE_M of the body (_body_destination: the squad's
## casualty collection point, or an active extraction point). Proposed numbers.
const BODY_QUIET_S := 30.0
const BODY_TAKE_M := 120.0
## A body this close to where it was being taken is there (laid down, not lifted again).
const BODY_THERE_M := 4.0
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
## Proposed (casualty suite, 2026-10-14: hit while bounding to cover, a squadmate started his
## own tourniquet at a run and lost it): self-treatment starts once he's below this speed.
const SELF_CARE_STILL_MPS := 2.0
## The escort leading him keeps this close to the lead, from his side (proposed; Captain,
## 2026-10-14: formation slots are wider now, and the HVT stays with the lead, not out on a
## wing or at the back of the second fire team).
const ESCORT_LEAD_M := 5.0
const ESCORT_LEASH_M := 3.0
const ESCORT_REACT_S := Vector2(1.6, 0.6)
const ESCORT_SUPPRESSED_S := 1.0
const GRAB_M := 1.6
const GRAB_CHANCE := 0.55
const GRAB_SKILL := 0.25
const GRAB_RETRY_S := 1.5
const HVT_MEDIC_PULL := 0.25
## Meta on a wounded HVT: the instance id of the medic walking in to take him over from his
## escort (care_by stays the escort's until the medic is beside him; handoff_medic).
const HANDOFF_META := &"medic_handoff"
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
## Dragging a casualty to cover: no closer to the cover spot for DRAG_STUCK_S (blocked, or the
## spot can't be reached), or out of contact for DRAG_QUIET_S, and the casualty is put down
## where they are and treated (Captain, 2026-10-14, P0914: "Dragging to cover" for minutes after
## the fight, the casualty held and untreated). Proposed.
const DRAG_STUCK_S := 8.0
const DRAG_QUIET_S := 3.0
const DRAG_PROGRESS_M := 0.5
const REACH_SKIP_S := 20.0
## Proposed: while clearing or assaulting through a position, unconscious foes this close get
## dead-checked (shot); otherwise targeting skips them.
const DEAD_CHECK_M := 8.0
## Proposed (Captain, P0362: dead-checks fired bursts until the body died, nearly always of a
## head or neck round): a dead-check is a look (DEAD_CHECK_LOOK_*_S, skill 0 and 1), then
## DEAD_CHECK_ROUNDS deliberate single rounds to the torso, each only with the sights within
## DEAD_CHECK_GATE_DEG and on the body (not the head); then the body counts as checked. One he
## can't get a clean shot at within DEAD_CHECK_GIVE_UP_S after the look counts as checked too.
const DEAD_CHECK_LOOK_UNSKILLED_S := 2.0
const DEAD_CHECK_LOOK_SKILLED_S := 1.0
const DEAD_CHECK_GATE_DEG := 1.0
const DEAD_CHECK_ROUNDS := 2
const DEAD_CHECK_GIVE_UP_S := 4.0
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
## isn't in it, unless the line goes through them (within MUZZLE_BODY_M: right in front of the
## barrel; playtest P0331, a squadmate shot one at 0 m).
const DOWNRANGE_M := 60.0
const LYING_EXTRA_M := 0.6
const MUZZLE_M := 0.5
const MUZZLE_BODY_M := 0.35
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
## A frag goes only where the shooter is known to within this (seen, or his fire placed; G-03).
const FRAG_MAX_ERR_M := 4.0
const SHARE_CONTACT_M := 80.0
## Contact passed on (queue 17 part 3): seconds by voice, by radio beyond SHARE_CONTACT_M
## (both need a radio; proposed).
const SHARE_VOICE_S := 1.0
const SHARE_RADIO_S := 2.5
const RADIO := &"radio"
## Friendlies see this far (hostiles SIGHT_RANGE) and stay in contact this long after the last
## sign of the enemy (hostiles CONTACT_MEMORY_S).
const SQUAD_SIGHT_RANGE := 300.0  # (was 120 m; Captain, 2026-10-13)
## How far out a fighter picks targets (AI bar G-27): by the weapon in hand and its optic, so a
## rifle with irons or a red dot doesn't snipe and a scoped one reaches past them. REACH_IRONS_M
## (SIGHT_RANGE, as before) at 1x, REACH_PER_POWER more for each power of the optic's highest
## magnification, to REACH_MAX_M; a pistol REACH_PISTOL_M. Past HOLDOVER_FROM_M the AI holds
## over for the drop (Ballistics.drop_m), as well as its skill judges it. Proposed numbers.
const REACH_IRONS_M := 300.0
const REACH_PER_POWER := 0.2
const REACH_MAX_M := 700.0
const REACH_PISTOL_M := 60.0
const HOLDOVER_FROM_M := 150.0
## Getting down (AI bar G-05, with G-17's folds; the Captain, 2026-10-19: soldiers in defilade, a
## man prone behind a fold in the ground firing over it). In a fight (not ordered a stance, not
## moving unless pinned, the enemy PRONE_MIN_M or more off) he goes prone when, lying there, his
## eye (PRONE_EYE_M) sees the enemy and either the ground in front hides him lying down
## (FOLD_HIDDEN_M: a fold, a crest, a berm) or the enemy is PRONE_OPEN_M or more off; pinned in
## the open he gets flat at once (a friendly crawls to cover, PRONE_SPEED). Checked every
## STANCE_CHECK_S. A fold also counts as cover when one is looked for (find_cover). Proposed.
const PRONE_MIN_M := 25.0
const PRONE_OPEN_M := 100.0
const PRONE_EYE_M := 0.4
const FOLD_HIDDEN_M := 0.2
const STANCE_CHECK_S := 1.0
const FOLD_BONUS := 2.0
## Fire by range (AI bar G-09): full bursts inside BURST_CLOSE_M, short ones out to BURST_FAR_M,
## single aimed shots past it; the pause between bursts grows PAUSE_PER_M a metre past
## BURST_CLOSE_M, to PAUSE_MAX_MULT. Machine guns keep their bursts at every range. Doctrine's
## burst and burst_pause scale both (G-15: insurgents long bursts, PMC controlled). Proposed.
const BURST_CLOSE_M := 30.0
const BURST_FAR_M := 150.0
const PAUSE_PER_M := 1.0 / 150.0
const PAUSE_MAX_MULT := 2.5
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
## Friendlies only, detection and reaction speed only (never aim error): never slower to spot
## or to react than EnemyResponse.HUNTER_COMBAT (0.7), win 6d's hunter squads and their named
## nemesis version (0.7..0.95). Captain, 2026-10-18, live playtest of v0.4.41: "friendly ai need
## a bit of a buff compared to new enemies. late reaction times" - a green recruit's own skill
## (roster.gd _ai_stats: 0.3 + 0.6 x aim, as low as 0.45 at hire) was setting Spotting.spot_seconds
## and _acquire's `react`, both skill-scaled, well below the hunters that recruit now has to face,
## so the newer, tougher side always won the draw. Aim error (_aim_error_deg) stays on the real
## skill: this buffs reflexes, not marksmanship.
const FRIENDLY_REACT_FLOOR := 0.7
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
var _crouch_kept := false  # the crouch the body was last given (_hold_crouch)
var _crouch_kept_at := -1000.0
var _heal_until := -1000.0
## Self-care put this unit prone (out in the open under fire); _act stands him back up once
## he's done.
var _care_prone := false
var _suppress_jitter := Vector3.ZERO
## "Drop packs here": the pack this unit left on the ground ({"id", "uid", "pos"}: its item,
## that very WorldItem's uid, where it went down), {} for none.
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
## How fast a carrier or dragger turns to the way it goes, of TURN_RATE.
const CARRY_TURN_MULT := 0.45
## Dragging (Care.DRAG): the nearest it got to _cover_point, when it last got nearer, and when
## contact was last seen (_drag_stalled).
var _drag_best := INF
var _drag_moved_at := 0.0
var _drag_contact_at := 0.0
var _has_cover := false
var _hold_point := Vector3.ZERO
var _held_since := -1.0  # when he got to _hold_point (Soldier._now()), -1 while away from it
var _dig_way := Vector3.ZERO  # the way his cover at _hold_point faces (_dig_in)
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
## A site garrison's post (GarrisonPost: held, in ambush, until it breaks), or null.
var post: GarrisonPost
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
var _fire_line := {}  # the last line-of-fire check (_fire_line): {"at", "from", "to", "state"}
var _no_shot_since := -1.0  # when this unit last found it had a mark but no line of fire (-1: it has one)
var _fire_spot: Variant = null  # where a base of fire / Suppress unit moves to get its shot (_find_fire_spot)
var _overwatch_taken: Variant = null  # the plan's high ground last taken up (_take_overwatch)
var _auto_prone := false  # down on his own (G-05), not by an order
var _stance_at := -1000.0  # when _auto_stance last cast its rays
## Men of a base of fire on high ground stand this far round its spot (G-17). Proposed.
const OVERWATCH_SPREAD_M := 3.0
var _fire_spot_aim := Vector3.INF  # the aim that spot was found for
var _fire_spot_stand := false  # the line there is from his feet, not a crouch
var _fire_spot_at := -1000.0  # when he last looked for one
var _asked_medic := false
var _answered := false
var _medic_called_at := -1000.0
var _ammo_given_at := -1000.0
var _reach_best := INF  # closest this unit got to its casualty on the way (Care.REACH)
var _reach_progress_at := 0.0  # when it last got REACH_PROGRESS_M closer
var _detour := Vector3.ZERO  # a sidestep around something in the way
var _detour_until := -1.0
var _detour_next := -1.0  # no new sidestep before then (try the direct way in between)
var _detour_side := 1.0
var _skip := {}  # casualty instance id -> Soldier._now() until which this unit leaves them to others
var _dead_check: Soldier  # an unconscious foe being dead-checked, kept until checked, dead or out of range
var _dead_check_rounds := 0  # rounds fired at _dead_check
var _dead_check_since := -1000.0  # when _dead_check became that body
var _checked := {}  # instance id -> true: bodies this unit has dead-checked (cleared when they're up again)
## Close-range aim (_acquire, _cqb_aim_point): the first-shot offset (metres, right/up), the
## offset held through this burst, seconds since the target was acquired, its reaction time,
## how long he holds before turning, and whether it was up when acquired.
var _acq_offset := Vector2.ZERO
var _burst_offset := Vector2.ZERO
var _burst_hold := Vector2.ZERO  # radians right/up: this burst's hold at range (RANGE_HOLD_*_DEG)
var _acq_age := 0.0
var _acq_react_s := 0.0
var _acq_hold_s := 0.0
var _acq_up := true
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


## Timing (tests/perf_timing.gd turns it on): microseconds spent in each part of the tick, summed
## over every brain, and the most any one call took.
static var profiling := false
static var prof := {}


static func _p(part: StringName, since: int) -> int:
	var now := Time.get_ticks_usec()
	if profiling:
		var e: Array = prof.get(part, [0, 0, 0])
		var took := now - since
		prof[part] = [int(e[0]) + took, int(e[1]) + 1, maxi(int(e[2]), took)]
	return now


func _physics_process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_tick(delta)
	FrameCost.spent(&"ai", started)


func _tick(delta: float) -> void:
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
			if squad != null and care in [Care.REACH, Care.DRAG, Care.TREAT, Care.CARRY]:
				squad.rescuer_down_at = now  # the next one doesn't walk into the same fire
				squad.rescuer_down_point = body.global_position
			_end_care()
		if loot_body != null:
			_end_scavenge()  # let go of the body, so a bearer waiting on it isn't stuck
		body.ai_status = body.vitals.condition_text()
		return
	_grenade_cd -= delta
	_cover_cd -= delta
	var t := Time.get_ticks_usec()
	_notice_fire(now)
	t = _p(&"notice_fire", t)
	if body.threat_time > _last_contact:
		_last_contact = body.threat_time
	if not _reports.is_empty():
		_take_reports(now)
	t = _p(&"reports", t)
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = SCAN_S
		var previous := target
		target = _find_target()
		t = _p(&"find_target", t)
		if target != null and (target != previous or target.vitals.is_up() != _acq_up):
			_acquire(target)  # reaction time, first-shot error, snap-aim hold (or a dead-check's look)
			if target != previous and target.vitals.is_up():
				var callouts := Callouts.of(body)
				if callouts:
					callouts.contact(body, target)
				if body.faction == &"hostile":
					Alert.server_sighting(body, target.global_position)  # hot zones: he'll radio it in (4B part 3)
	t = _p(&"acquire", t)
	if target != null and target.vitals.is_up():
		_last_contact = now
		body.threat_pos = target.global_position
		body.threat_err = 0.0
		body.threat_time = now
		_no_los_s = 0.0
		if _scan_cd == SCAN_S:
			_share_contact(target.global_position, now)  # once a scan, not every frame
			if squad:
				squad.note_enemy(target, target.global_position)
	else:
		_no_los_s += delta  # a body being dead-checked is no contact
	t = _p(&"contact", t)
	_think_cd -= delta
	if _think_cd <= 0.0:
		_think_cd = THINK_S
		_update_morale(THINK_S)
		t = _p(&"morale", t)
		_choose_intent()
		t = _p(&"choose_intent", t)
	_act()
	t = _p(&"act", t)
	_steer(delta)
	t = _p(&"steer", t)
	_shoot()
	t = _p(&"shoot", t)
	_hold_crouch()
	body.ai_status = status_text()
	_p(&"status", t)


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


## `combat` for detection and reaction speed (Spotting.spot_seconds, _acquire's `react` and
## _acq_hold_s): floored at FRIENDLY_REACT_FLOOR for friendlies so a green recruit reacts no
## slower than the hunter tier he now faces. Aim error and first-shot offset keep the real skill.
func _react_combat() -> float:
	return maxf(combat, FRIENDLY_REACT_FLOOR) if _friendly() else combat


## An enemy medic able to work: not pinned or stunned.
func _enemy_medic_free() -> bool:
	return not _friendly() and body.role == Roles.MEDIC and body.suppression < PINNED and body.stunned_s <= 0.0


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
	if Soldier._now() - _hold_for_cover_at < 1.0:
		return true  # holding back from a casualty in the kill zone: suppress the shooter
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var other := SquadAI.of(n)
		if other and other != self and other.body != null and other.body.faction == body.faction and other.body.vitals.is_up() \
				and other.intent == Intent.CASUALTY and other.care in [Care.REACH, Care.DRAG] \
				and other.body.global_position.distance_to(body.global_position) <= COVER_MEDIC_M:
			return true
	return false


## Going for `c` now would feed the squad into the fire on them: a rescuer went down near
## them lately (HOT_DOWN_S), or (Captain, 2026-10-17: "rescuers going for dangerous rescues
## instead of kills or cover") the casualty lies in the open to a known shooter the squad is
## still trading fire with (fired on within RESCUE_QUIET_S), with nothing covering the rescue:
## no smoke on them, the shooter not pinned, no squadmate putting fire on it (shot within
## COVERING_FIRE_S), and this unit carries no smoke to screen its own way in (_care_reach throws
## it). Then even the first rescuer waits: it puts fire on the shooter from cover
## (_medic_needs_cover) until one of those changes.
const RESCUE_QUIET_S := 6.0
const COVERING_FIRE_S := 3.0


## A squadmate (not this unit) fired within COVERING_FIRE_S: the rescue has covering fire.
func _covering_fire() -> bool:
	for m: Soldier in squad.members():
		if m != body and is_instance_valid(m) and m.vitals.is_up() and Soldier._now() - m.last_shot_at < COVERING_FIRE_S:
			return true
	return false


func _rescue_hot(c: Soldier) -> bool:
	if not in_contact() or squad == null or _sheltered(c) or _screened(c.global_position):
		return false
	var now := Soldier._now()
	var down := now - squad.rescuer_down_at < HOT_DOWN_S and squad.rescuer_down_point.distance_to(c.global_position) < HOT_DOWN_M
	var under_fire := now - squad.engaged_at < RESCUE_QUIET_S
	if not down and not under_fire:
		return false
	if not down and (body.inventory.count_of(SCREEN_SMOKE) > 0 or _covering_fire()):
		return false  # it can screen its own way in, or the squad has the shooter's head down
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var f := n as Soldier
		if f != null and f.faction != body.faction and f.vitals.is_up() and f.global_position.distance_to(body.threat_pos) < 4.0 				and f.suppression >= PINNED:
			return false  # base of fire has them pinned
	return true


## This unit, or its squad, was fired upon recently.
func engaged() -> bool:
	return Soldier._now() - _fired_on_at < CONTACT_MEMORY_S or (squad != null and squad.is_engaged())


## Whether the orders and combat mode let this unit shoot at what it sees now.
func weapons_free() -> bool:
	if hold_fire:
		return false
	if post:
		return post.sprung  # a garrison holds its fire in ambush, then every man opens up (GarrisonPost)
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
	if not _ready_done:
		# 2026-10-14 (helicopter insertion): an AI seated aboard before its first physics
		# frame (its brain is off while seated) gets its order on the way out: set up first.
		_setup()
	order = new_order
	if body == null:
		return
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
	var no_shot := _no_shot_text()
	if no_shot != "":
		return no_shot
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
			var level := CompoundLevel.current(body)
			var d := level.get_node_or_null(Digging.NODE_NAME) as Digging if level else null
			return "Digging in" if d and d.digging(body) else "Holding"
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
	if _friendly() and squad and is_instance_valid(squad.leader):
		return "Following (%s)" % squad.formation_text(body.fire_team if body.fire_team >= 0 else 0)
	return "Following"


# --- Setup ----------------------------------------------------------------

func _setup() -> void:
	body = get_parent() as Soldier
	if body == null or not body.is_node_ready():
		return
	_hold_point = body.global_position
	_move_point = body.global_position
	morale = _morale_base()
	# AI spawned together (a squad, a garrison) would otherwise scan and think in the same
	# frames for good: a random start spreads them out (research 2026-10-13 B2.6).
	_scan_cd = randf() * SCAN_S
	_think_cd = randf() * THINK_S
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
				# (An ordered tactic is the newer order: Suppress plays out by fighting from here.)
				scores[Intent.HOLD] = PLAYER_ORDER_SCORE if ordered.is_empty() else 0.5
			Squad.Order.MOVE:
				# A player's move order rules until it gets there; then it becomes a real Hold
				# (Captain, 2026-10-18: "running around" when ordered to stand somewhere - scoring
				# an arrived move at 0.5, FOLLOW's own baseline, let squad tactics (TACTIC_SCORE
				# 0.75), casualty care and escort pull it straight off the spot it was told to
				# hold; a Hold's own PLAYER_ORDER_SCORE keeps it there the same way an explicit
				# Hold order does).
				if body.global_position.distance_to(_move_point) <= ARRIVE + 0.5:
					order = Squad.Order.HOLD
					_hold_point = _move_point
					scores[Intent.HOLD] = PLAYER_ORDER_SCORE if ordered.is_empty() else 0.5
				else:
					scores[Intent.MOVE_TO] = 0.5 if not ordered.is_empty() else PLAYER_ORDER_SCORE
		if escort_valid():
			scores[Intent.ESCORT] = ESCORT_SCORE
		elif escorting != null:
			set_escort(null)
	else:
		scores[Intent.PATROL] = 0.3
		if post:
			post.update(Soldier._now())
			if post.fleeing:
				if _fall_back_point == null:
					_fall_back_point = post.flee_point(body.global_position)
					_callout(&"tactic", "Get out! Fall back!")
				scores[Intent.FALL_BACK] = 0.92  # a broken garrison runs: above fighting and care in contact
		if Soldier._now() - _last_contact < INVESTIGATE_MEMORY_S or suspecting():
			# Shaken (losses, suppression), it stays put in cover rather than searching the kill zone.
			scores[Intent.INVESTIGATE] = 0.55 if morale >= MORALE_SHAKEN + 0.2 or suspecting() else 0.2
	# Casualty care, both sides: a living casualty comes before almost anything; a fallen
	# friendly's body is carried only out of contact.
	_candidate = _find_casualty() if care == Care.NONE or care == Care.BODY else null
	if (care != Care.NONE and care != Care.BODY) or _candidate != null:
		# In contact a casualty waits on the squad's tactics; ordered to hold, one near the spot
		# is still seen to (above the hold), farther ones wait on the order.
		var who: Soldier = casualty if care != Care.NONE and care != Care.BODY and is_instance_valid(casualty) else _candidate
		var near_hold := order == Squad.Order.HOLD and who != null and who.global_position.distance_to(_hold_point) <= HOLD_CARE_M
		var in_fire := CASUALTY_CONTACT_SCORE if _friendly() else (HOSTILE_MEDIC_CONTACT_SCORE if _enemy_medic_free() else HOSTILE_CARE_CONTACT_SCORE)
		scores[Intent.CASUALTY] = PLAYER_ORDER_SCORE + 0.01 if near_hold else (in_fire if contact else 0.9)
	elif not contact and (care == Care.BODY or _find_body() != null):
		scores[Intent.CASUALTY] = BODY_RECOVER_SCORE
	_maybe_call_medic()
	_maybe_resupply_gunner(Soldier._now())
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
	# The escort's own wounded HVT takes priority even while contact is remembered:
	# care's 0.82 beats escort's 0.75, but not its usual switching margin of 0.1.
	var escort_care := intent == Intent.ESCORT and best == Intent.CASUALTY and _candidate == escorting and escort_valid()
	if best != intent and best_score < current + HYSTERESIS and not escort_care:
		return
	if best != intent:
		var player_order := _friendly() and (best == Intent.MOVE_TO or best == Intent.HOLD or (best == Intent.TACTIC and not ordered.is_empty()))
		var enemy_under_fire := not _friendly() and in_contact() and not _enemy_medic_free()  # the enemy leaves him to fight (a free medic stays)
		if intent == Intent.CASUALTY and care != Care.NONE and care != Care.BODY and best_score < 0.95 and not player_order and not enemy_under_fire:
			return  # don't abandon a casualty for anything short of an empty magazine, your own bleed or a player's order
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
				_fight(_formation_anchor(), 8.0)
			elif not _follow_up_to_lead():
				var spot := _follow_spot()
				_go(spot)
				if _halt_spot != null and _flat_distance(spot) <= ARRIVE + 0.3:
					_face(body.global_position + _outward(spot))  # halted: watch out from the lead
		Intent.HOLD:
			if fighting():
				_stop_digging()
				_fight(_hold_point, 4.0)
			else:
				_go(_hold_point, false)
				_dig_in()
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
	_keep_to_fire_spot()  # a base of fire with no line of fire: to where it has one
	_apply_combat_mode()
	if _care_prone and intent != Intent.HEAL:
		_care_prone = false
		body.want_stance = stance_order  # done treating himself: back to his own (or ordered) stance
	if stance_order >= 0 and not _care_prone:
		body.want_stance = stance_order if intent != Intent.CASUALTY else -1  # (casualty care kneels as it needs)
	elif not _care_prone:
		var low := _auto_stance() if intent == Intent.FIGHT else -1
		if low >= 0:
			body.want_stance = low
			_auto_prone = true
		elif _auto_prone:
			body.want_stance = -1
			_auto_prone = false


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
			# Following: only once the lead has halted (_halt_spot), not each time he reaches
			# his slot while the lead walks on (that bounced him up and down).
			if not fight and _halted() and (intent != Intent.FOLLOW or _halt_spot != null):
				body.want_crouch = true
		Squad.CombatMode.STEALTH:
			body.want_crouch = true


## Stance hysteresis (CROUCH_HOLD_S): what this tick wants, held to the last change for a
## moment, except going down when pinned or stunned.
func _hold_crouch() -> void:
	var want := body.want_crouch
	if want == _crouch_kept:
		return
	var now := Soldier._now()
	var hold := CROUCH_DOWN_HOLD_S if want else CROUCH_HOLD_S
	if (want and (body.suppression >= PINNED or body.stunned_s > 0.0)) or now - _crouch_kept_at >= hold:
		_crouch_kept = want
		_crouch_kept_at = now
	else:
		body.want_crouch = _crouch_kept


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
			_no_los_s = 0.0
			# Push one bound toward where the enemy was last seen: to cover, and only in good heart.
			var spot: Variant = find_cover(body.global_position.move_toward(body.threat_pos, ADVANCE_STEP), ADVANCE_COVER_M) if morale >= ADVANCE_MORALE else null
			if spot != null:
				_advancing = true
				_advance_anchor = spot
				_cover_point = spot
				_has_cover = true
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
			_fight(_formation_anchor(), 8.0)


## Where a following squadmate fights from: his formation slot (Captain, 2026-10-14: everyone
## used to fight from cover within 8 m of the lead, and in the open with none found came back
## to 4 m off him: the whole squad on the lead after every contact).
func _formation_anchor() -> Vector3:
	if squad == null or not is_instance_valid(squad.leader):
		return body.global_position
	return squad.follow_point(body)


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
	if _halt_spot != null and _flat_between(_halt_spot, slot) > HALT_COVER_M + 0.5:
		_halt_spot = null  # the slot moved on (his team leader got to his place): find one by it again
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
		if other and other != self and other._halt_spot != null and (other._halt_spot as Vector3).distance_to(point) < COVER_GAP_M:
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
	_callout_reload(weapon)


# --- Casualty care --------------------------------------------------------

## Whether `s` needs someone else's help: unconscious (downed, players too), or conscious
## and calling for a medic (a player: player_wants_care). The dead are bodies, not casualties.
static func needs_help(s: Soldier) -> bool:
	if s == null or not is_instance_valid(s) or s.is_queued_for_deletion() or s.vitals.is_dead():
		return false
	if s.vitals.downed:
		return true
	if not s.is_ai():
		return player_wants_care(s)
	if Person.is_hvt(s):
		return s.vitals.care_needed().any(func(t: Dictionary) -> bool: return String(t.kind) in HVT_CARE_KINDS)
	var ai := SquadAI.of(s)
	return ai != null and ai.asking_for_medic()


## A conscious player wants a squadmate's care (Captain, 2026-10-19): he called for a medic or
## told one to treat him in the last MEDIC_CALL_S (Soldier.medic_asked_at), or, on its own, he has
## a wound he carries nothing to treat (out of a firefight; in one, only massive bleeding).
static func player_wants_care(s: Soldier) -> bool:
	var tasks := s.vitals.care_needed()
	if tasks.is_empty():
		return false
	if Soldier._now() - s.medic_asked_at < MEDIC_CALL_S:
		return true
	var lvl := CompoundLevel.current(s)
	var squad := lvl.squad_for(s.faction) if lvl else null
	var engaged := squad != null and squad.is_engaged()
	for t: Dictionary in tasks:
		if engaged and String(t.kind) not in UNDER_FIRE_KINDS:
			continue
		if not Vitals.task_items(t).any(func(id: StringName) -> bool: return s.inventory.count_of(id) > 0):
			return true  # nothing of his own for it: a squadmate comes
	return false


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
var _hold_for_cover_at := -1000.0
const HOT_DOWN_S := 25.0
const HOT_DOWN_M := 25.0


func _free_for(c: Soldier) -> bool:
	return _ready_done and body != null and body != c and body.vitals.is_up() and not body.is_queued_for_deletion() \
		and (care == Care.NONE or care == Care.BODY or casualty == c) and not _skipping(c) \
		and (not escort_valid() or c == escorting) and not is_instance_valid(body.vehicle)  # seated: can't reach anyone (G-01)


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


## A player told this one to treat him ("Treat me", Soldier.medic_asked_at / meta "medic_pick")
## in the last MEDIC_CALL_S.
func _picked_for(c: Soldier) -> bool:
	return c != null and not c.is_ai() and Soldier._now() - c.medic_asked_at < MEDIC_CALL_S and String(c.get_meta(&"medic_pick", "")) == String(body.name)


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
		if not _friendly() and (in_contact() or Soldier._now() - _last_contact < HOSTILE_CARE_HOT_S) 				and SquadAI.of(s) != null and SquadAI.of(s).squad != squad 				and not (_enemy_medic_free() and body.global_position.distance_to(s.global_position) <= HOSTILE_MEDIC_REACH_M):
			continue  # the enemy in a fight: only its own team's casualties (a medic: anyone close)
		# A player told one of us to treat him ("Treat me"): while that's fresh, that one goes
		# and the rest leave him to it (whoever was on him already too).
		var pick := String(s.get_meta(&"medic_pick", "")) if not s.is_ai() and Soldier._now() - s.medic_asked_at < MEDIC_CALL_S else ""
		if _picked_for(s):
			return s
		if pick != "":
			var picked := body.get_parent().get_node_or_null(NodePath(pick)) as Soldier if body.get_parent() else null
			if picked and picked.vitals.is_up():
				continue
		var carer := _carer_of(s)
		if carer == body:
			return s
		var hvt := Person.is_hvt(s)
		if hvt and not s.vitals.downed and _next_task(s, false).is_empty():
			continue  # nothing this unit can do for a conscious HVT
		if carer != null:
			var carer_ai := SquadAI.of(carer)
			if hvt and _handoff_by_other(s):
				continue  # another medic is already walking in to take him over
			if hvt and _takes_over_hvt(s, carer):
				pass  # a medic takes a wounded HVT over from whoever has him
			elif carer_ai == null or not carer_ai.wants_medic or medic_for(s, carer_ai.wanted) != body:
				continue  # someone is on it
		else:
			var ai := SquadAI.of(s)
			var asked: Array[StringName] = ai.wanted if ai and not s.vitals.downed else ([] as Array[StringName])
			if responder_for(s, asked) != body:
				continue
			if _rescue_hot(s):
				_hold_for_cover_at = Soldier._now()
				continue  # secure first: base of fire, smoke or a flank, then one goes in
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


## A friendly's dead body this unit chooses to take somewhere (_body_destination; BODY_QUIET_S
## out of contact): the body's battle buddy goes first, otherwise the nearest free non-medic.
## None in a normal situation, and none while the squad holds casualties (Squad.hold_casualties).
func _find_body() -> Soldier:
	if body.faction != &"friendly" or squad == null or not is_instance_valid(squad.leader) or body.carrying != null \
			or squad.hold_casualties:
		return null
	var best: Soldier = null
	var best_d := BODY_RECOVER_M
	for n in get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
		var s := n as Soldier
		if s == null or s.is_queued_for_deletion() or s.faction != body.faction or is_instance_valid(s.carried_by) \
				or _carer_of(s) != null or _body_destination(s.body_point()) == null:
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


## Free to carry a body: not looking after anyone, not carrying, hands free, out of contact
## BODY_QUIET_S, nothing ordered and not busy with its own wounds.
func _can_bear(dead: Soldier) -> bool:
	return care == Care.NONE and _free_for(dead) and body.carrying == null and body.inventory.hands == &"" \
		and Soldier._now() - _last_contact >= BODY_QUIET_S and ordered.is_empty() and scavenge_order == null \
		and _self_care_score() <= 0.0 and not asking_for_medic()


## Where a fallen friendly's body at `at` could be taken, or null: the squad's casualty
## collection point (Squad.ccp_point), else the nearest point of an active extraction, within
## BODY_TAKE_M of it. Null too once it lies within BODY_THERE_M of that place.
func _body_destination(at: Vector3) -> Variant:
	if squad == null or squad.hold_casualties:
		return null
	var best: Variant = null
	var ccp: Variant = squad.ccp_point()
	if ccp != null:
		best = ccp
	else:
		var extraction := MapNodes.extraction(body)
		if extraction and extraction.is_active():
			for p: Dictionary in extraction.points:
				var v: Vector2 = p.get("pos", Vector2.INF)
				var there := Vector3(v.x, at.y, v.y)
				if v.is_finite() and (best == null or _flat_between(there, at) < _flat_between(best, at)):
					best = there
	if best == null:
		return null
	var d := _flat_between(best, at)
	return best if d <= BODY_TAKE_M and d > BODY_THERE_M else null


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
	if not is_instance_valid(casualty) or casualty.is_queued_for_deletion() or casualty.vitals.is_dead():
		_end_care()
		_think_cd = 0.0
		return
	if casualty.care_by != body:
		var carer := _carer_of(casualty)
		if carer == null or _picked_for(casualty):
			casualty.care_by = body  # (a player's "Treat me" pick takes him over from whoever had him)
			_clear_handoff(casualty)
		elif care == Care.REACH and Person.is_hvt(casualty) and _takes_over_hvt(casualty, carer):
			# The escort keeps treating while the medic approaches. Claiming from afar
			# made him abandon care before the medic was actually beside the HVT.
			_care_reach(in_contact(), true)
			return
		else:
			_end_care()  # someone else took over
			_think_cd = 0.0
			return
	var contact := in_contact()
	match care:
		Care.REACH:
			_care_reach(contact)
		Care.DRAG:
			if body.carrying != casualty:
				care = Care.TREAT
			elif _has_cover and not _at_cover() and not _drag_stalled(contact):
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
	if carer == null or carer == body or _picked_for(c):
		return true
	if Person.is_hvt(c) and _handoff_by_other(c):
		return false  # another medic is already walking in to take him over
	if Person.is_hvt(c) and _takes_over_hvt(c, carer):
		return true
	var carer_ai := SquadAI.of(carer)
	return carer_ai != null and carer_ai.wants_medic and medic_for(c, carer_ai.wanted) == body


## This unit (a free medic) takes wounded HVT `c` over from `carer`, who isn't a medic: the
## escorts' care is a stopgap until a medic is there. One medic walks in at a time: not while
## another is already on his way to him (handoff_medic).
func _takes_over_hvt(c: Soldier, carer: Soldier) -> bool:
	return _may_hand_over(c, carer) and not _handoff_by_other(c)


## This unit is a free medic who could take wounded HVT `c` over from non-medic `carer`.
func _may_hand_over(c: Soldier, carer: Soldier) -> bool:
	return body.role == Roles.MEDIC and carer != body and carer.role != Roles.MEDIC and _free_for(c) and _cares_for(c)


## The medic walking in to take wounded HVT `c` over from his escort (still on his way, up, and
## still after `c`), or null; a stale claim (he went down, gave up or took someone else) is
## dropped.
static func handoff_medic(c: Soldier) -> Soldier:
	if c == null or not is_instance_valid(c) or not c.has_meta(HANDOFF_META):
		return null
	var medic := instance_from_id(int(c.get_meta(HANDOFF_META))) as Soldier
	var ai := SquadAI.of(medic) if medic != null else null
	if ai == null or medic.is_queued_for_deletion() or not medic.vitals.is_up() or ai.casualty != c or ai.care != Care.REACH:
		c.remove_meta(HANDOFF_META)
		return null
	return medic


## Another medic than this unit is walking in on wounded HVT `c`.
func _handoff_by_other(c: Soldier) -> bool:
	var medic := handoff_medic(c)
	return medic != null and medic != body


## Drops this unit's walking-in claim on `c` (arrived, or let him go).
func _clear_handoff(c: Soldier) -> void:
	if is_instance_valid(c) and c.has_meta(HANDOFF_META) and int(c.get_meta(HANDOFF_META)) == body.get_instance_id():
		c.remove_meta(HANDOFF_META)


## Takes `c` on (from nobody, or from a carer who asked for a medic).
func _take_casualty(c: Soldier) -> void:
	if care != Care.NONE:
		_end_care()
	casualty = c
	var carer := _carer_of(c)
	if carer != null and carer != body and Person.is_hvt(c) and _may_hand_over(c, carer):
		# A medic for a wounded HVT his escort is treating: the escort keeps care_by until the
		# medic is beside him (_care_reach), and other medics leave him to this one meanwhile
		# (an order to treat him makes this one the medic walking in).
		c.set_meta(HANDOFF_META, body.get_instance_id())
	else:
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
func _care_reach(contact: bool, handoff := false) -> void:
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
	if handoff:
		casualty.care_by = body
		_clear_handoff(casualty)
	# (Never lift someone another is treating: it cut the Captain's IV short, P0164.)
	if exposed and not is_instance_valid(casualty.carried_by) and not casualty.vitals.is_healing():
		var spot: Variant = find_drag_cover(body.global_position, 10.0)
		if spot != null and body.server_pick_up_body(casualty, Soldier.DRAG):
			_cover_point = spot
			_has_cover = true
			care = Care.DRAG
			_start_drag_watch()
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
		return true  # an HVT goes with the squad, not left lying (even under the hold below)
	if squad and squad.hold_casualties and _friendly():
		return false  # "Stop bringing casualties": they're looked after where they lie
	var ccp: Variant = squad.ccp_point() if squad else null
	if ccp != null and _friendly():
		return casualty.body_point().distance_to(ccp) > LAY_NEAR_M + 1.0  # "Bring casualties here"
	if _friendly() and order == Squad.Order.MOVE and _lay_spot != null and _lies_at(_lay_spot):
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
## waking up, sends this unit back to treating them. Under "Stop bringing casualties"
## (Squad.hold_casualties, Captain 2026-10-14) out of contact the carrier lays them down where
## he is and treats or watches over them there; a contact drag to cover and an HVT's carry
## still happen under it.
func _care_carry(contact: bool) -> void:
	if contact:
		if body.carrying == casualty:
			body._set_carry_mode(Soldier.DRAG, &"grab")
			var spot: Variant = find_drag_cover(body.global_position, 10.0)
			_has_cover = spot != null
			if spot != null:
				_cover_point = spot
			care = Care.DRAG
			_start_drag_watch()
		else:
			care = Care.GUARD
		return
	if squad and squad.hold_casualties and _friendly() and not Person.is_hvt(casualty):
		if body.carrying == casualty:
			body.server_put_down()
			var callouts := Callouts.of(body)
			if callouts:
				callouts.putting_down(body, casualty, false)
		_has_destination = false
		care = Care.TREAT
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
		if body.carrying != casualty and _lies_at(lay):
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


## Out of contact: picks up a fallen friendly's body and takes it where it's going
## (_body_destination), and says so. Contact, "Stop bringing casualties" or getting there puts
## it down (and says that too).
func _carry_body() -> void:
	var dest: Variant = _body_destination(casualty.body_point()) if is_instance_valid(casualty) and not casualty.is_queued_for_deletion() else null
	if in_contact() or dest == null or (is_instance_valid(casualty.carried_by) and casualty.carried_by != body) \
			or not is_instance_valid(squad.leader):
		if is_instance_valid(casualty) and body.carrying == casualty:
			var callouts := Callouts.of(body)
			if callouts:
				callouts.putting_down(body, casualty, true)
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
	_go(dest)


func _callouts_carrying(dead: bool) -> void:
	var callouts := Callouts.of(body)
	if callouts:
		callouts.carrying(body, casualty, dead)


func _end_care() -> void:
	if is_instance_valid(casualty):
		_clear_handoff(casualty)
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
			_go(_escort_lead_spot())  # he follows this unit
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
		var hvt_brain := h.get_node_or_null(NodePath(PeopleLayer.BRAIN)) as HvtAI
		if hvt_brain:
			hvt_brain.held_by = body  ## Captain, 2026-10-14: grabbed holds until let go
			hvt_brain.bolted_at = -1.0
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
		var d := body.global_position.distance_to(dead.body_point())  # where it lies, not its capsule
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
			and dead.body_point().distance_to(squad.leader.global_position) > SCAVENGE_LEASH_M:
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
## times, not one the casualty is doing on themselves right now (on itself: not one its carer
## is doing on it right now), and (on itself) not one a medic keeps for the squad (_kept_for_squad), nor an IV or IO on itself; {} for none. Where
## several items would do, the task's "item" becomes the first one carried (Vitals.pick_item),
## out of the casualty's own kit first ("their_kit": _pick_for).
func _next_task(c: Soldier, under_fire: bool) -> Dictionary:
	var conscious := c.vitals.is_up() or c.vitals.why_unconscious().has(&"pain")  # morphine wakes one out from pain
	var their := SquadAI.of(c) if c != body else null
	var carer := SquadAI.of(c.care_by) if c == body and is_instance_valid(c.care_by) else null
	for task in plan_care(c.vitals.care_needed(), under_fire, conscious):
		if their and their._treat_until >= 0.0 and their._treat_key == _task_key(c, task):
			continue
		if carer and carer._treat_until >= 0.0 and carer._treat_target == c and carer._treat_key == _task_key(c, task):
			continue  # his carer is doing that one on him now
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
	var t0 := Time.get_ticks_usec()
	var t := morale_target()
	t0 = _p(&"morale_target", t0)
	morale = move_toward(morale, t, (MORALE_FALL_PER_S if t < morale else MORALE_RISE_PER_S) * dt)
	var state := "broken" if morale < MORALE_BROKEN else ("shaken" if morale < MORALE_SHAKEN else "steady")
	if state != _morale_state:
		print("[tactics] %s %s (morale %.2f)" % [body.name, state, morale])
		t0 = _p(&"morale_print", t0)
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
	var own := _self_task()
	if _own_tourniquet(own):
		return 0.97  # bleeding out: his own tourniquet, even with a squadmate on the way to him
	if _being_treated():
		return 0.92
	if own.is_empty():
		return 0.0
	if Soldier._now() < _heal_until:
		return 0.97  # told to patch up now
	return 0.75 if in_contact() else 0.62


## What this unit can do for itself right now (see _self_care_score), or {}.
func _self_task() -> Dictionary:
	if not body.vitals.is_up():
		return {}
	return _next_task(body, in_contact() and not _at_cover())


func _do_self_care() -> void:
	_has_destination = false
	body.want_crouch = true
	var task := _self_task()
	# Out in the open under fire he gets down where he is to put his tourniquet on: running
	# on for cover first costs blood, and a tourniquet started on the move is lost.
	if _own_tourniquet(task) and in_contact() and not _at_cover():
		_care_prone = true
		body.want_stance = SoldierMovement.Stance.PRONE
	if _treat_until >= 0.0 or Soldier._now() < body._busy_until:
		return
	if _being_treated() and not _own_tourniquet(task):
		return  # a squadmate is seeing to him: hold still (his own tourniquet never waits for one)
	if Vector2(body.velocity.x, body.velocity.z).length() > SELF_CARE_STILL_MPS:
		return  # still running from a bound: a treatment started on the move is lost ("you moved")
	if _care_prone and not body.movement.is_prone():
		return  # down first (a tick): the stance change doesn't land mid-treatment
	if not task.is_empty():
		_start_treatment(body, task)
		return
	_think_cd = 0.0


## `task` (one of _self_task's) is massive bleeding he stops himself, at once and before
## anything else: his own tourniquet.
static func _own_tourniquet(task: Dictionary) -> bool:
	return not task.is_empty() and String(task.kind) in UNDER_FIRE_KINDS


## A squadmate is with this conscious unit to treat it: hold still.
func _being_treated() -> bool:
	var carer := body.care_by
	if not is_instance_valid(carer) or not carer.vitals.is_up():
		return false
	var ai := SquadAI.of(carer)
	return ai != null and ai.casualty == body and ai.care in [Care.REACH, Care.TREAT] \
		and _flat_distance(carer.global_position) <= BEING_TREATED_M


## A conscious wounded unit that needs what it doesn't carry (or, a medic, keeps for the
## squad) calls "Medic!" (at most every MEDIC_CALL_S) and lists what it needs in `wanted`,
## once his own tourniquet (if he has one to put on) is on.
func _maybe_call_medic() -> void:
	if care != Care.NONE and care != Care.BODY:
		return
	var now := Soldier._now()
	if now - _medic_called_at < MEDIC_CALL_S or _being_treated() or not body.vitals.is_up():
		return
	if (_treat_until >= 0.0 and _treat_target == body) or _own_tourniquet(_self_task()):
		return  # his own tourniquet first: a medic called now reaches him mid-tourniquet and takes it over
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


## Ammo bearer (new role): out of contact, hands a belt box of belt_762x51 across to the
## nearest friendly heavy gunner within AMMO_RESUPPLY_M who's down to GUNNER_LOW_BELTS spare,
## at most every AMMO_RESUPPLY_COOLDOWN_S. First slice: opportunistic (it doesn't path to the
## gunner; normal formation/buddy movement is what brings them this close), the way scavenging
## only happens when a unit is already near the body it wants.
## Caliber-agnostic (Captain, 2026-10-17, "the new roles go to the factions too"): any belt-fed
## LMG counts as a gunner to resupply, not only Roles.HEAVY_GUNNER's own M240B, so the same
## ammo_bearer behaviour serves Black Ridge's PKM gunner and the autorifleman's M249 as well as
## Vantage's M240B, with no per-faction special-casing here.
func _maybe_resupply_gunner(now: float) -> void:
	if body.role != Roles.AMMO_BEARER or in_contact() or now - _ammo_given_at < AMMO_RESUPPLY_COOLDOWN_S:
		return
	var gunner := _nearest_gunner()
	if gunner == null or body.global_position.distance_to(gunner.global_position) > AMMO_RESUPPLY_M:
		return
	var ammo := StringName(ItemDB.get_item(gunner.inventory.slots.get(&"primary", &"")).stats.get("ammo", &""))
	if ammo == &"" or body.inventory.count_of(ammo) <= 0 or gunner.inventory.count_of(ammo) > GUNNER_LOW_BELTS:
		return
	if not body.inventory.remove_one(ammo):
		return
	gunner.inventory.take(ammo, 1)
	_ammo_given_at = now


## The nearest same-squad soldier still up whose primary is a belt-fed LMG, or null.
func _nearest_gunner() -> Soldier:
	if squad == null:
		return null
	var best: Soldier = null
	var best_d := INF
	for s: Soldier in squad.members():
		if s == body or not s.vitals.is_up():
			continue
		var weapon := ItemDB.get_item(s.inventory.slots.get(&"primary", &""))
		if weapon == null or not weapon.tags.has("lmg") or not weapon.tags.has("belt"):
			continue
		var d := body.global_position.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			best = s
	return best


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
			body.want_crouch = String(t.get("port", "")) not in ["window", "parapet"] and not (_foe() != null and Soldier._now() >= _pause_until)
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
		&"exo_in":
			_tactic_exo_in(t)
		&"climb":
			_tactic_climb(t)


## Climb order: to the spot, up every ledge in the way (the jump key's mantle), then hold.
func _tactic_climb(t: Dictionary) -> void:
	if _climb_toward(t, CLIMB_DONE_M) != CLIMB_GOING:
		_tactic_done(t)


## Climbing to t.point ("Climb up there", and a follower going up after its lead): walks to it,
## climbs (or, in a working LX-3, leaps) every ledge in the way. CLIMB_THERE once up there within
## `done_m` (or over a wall it leapt), CLIMB_CANT at a wall too high for it after
## CLIMB_GIVE_UP_S, else CLIMB_GOING.
const CLIMB_GOING := 0
const CLIMB_THERE := 1
const CLIMB_CANT := 2


func _climb_toward(t: Dictionary, done_m: float) -> int:
	var point: Vector3 = t.point
	var mv := body.movement
	if mv.mantling:
		_has_destination = false
		return CLIMB_GOING
	if t.get("leapt", false) and mv.last_over:
		return CLIMB_THERE  # an LX-3 leapt the wall: over it is where it was going (not back)
	var up_there := body.global_position.y >= point.y - CLIMB_UP_M
	var d := point - body.global_position
	var flat := Vector2(d.x, d.z).length()  # (not _flat_distance: the spot is a floor up, on purpose)
	if up_there and flat <= done_m:
		return CLIMB_THERE
	if up_there:
		_go(point)
		return CLIMB_GOING
	# Below it: at the wall (near the spot, or at the end of the walkable way toward it) it turns
	# to face the spot, and a ledge ahead is climbed.
	var stuck := not _path.is_empty() and _flat_distance(_path[_path.size() - 1]) < 1.0
	var at_wall := flat <= CLIMB_AT_WALL_M or stuck
	if at_wall and flat > 0.2:
		body.rotation.y = atan2(-d.x, -d.z)
	var ledge := mv.find_ledge() if mv.can_mantle() else {}
	if not ledge.is_empty() and (ledge.top as Vector3).y > body.global_position.y + 0.3:
		_has_destination = false
		body.want_mantle = true
		t.leapt = true
		if not t.has("tries_from"):
			t.tries_from = Soldier._now()
		if Soldier._now() - float(t.tries_from) > CLIMB_GIVE_UP_S * 2.0:
			return CLIMB_CANT  # the climb won't start (a capsule in the way): don't freeze trying
		return CLIMB_GOING
	if at_wall:
		if not t.has("at_wall"):
			t.at_wall = Soldier._now()
		if Soldier._now() - float(t.at_wall) > CLIMB_GIVE_UP_S:
			return CLIMB_CANT  # too high for these legs (or no room on top): it holds here
	_go(point, true)
	return CLIMB_GOING


## Following, the lead is up on a roof (FOLLOW_CLIMB_DY or more above, within FOLLOW_CLIMB_M)
## no walkable way reaches (Captain, 2026-10-17: "make sure squaddies also follow you onto the
## rooftop you jump onto if they can"): this unit climbs or leaps up after him (_climb_toward),
## stopping FOLLOW_CLIMB_NEAR_M off him. A roof out of its reach: it waits below and tries again
## after FOLLOW_CLIMB_RETRY_S. True while it's busy getting up there.
const FOLLOW_CLIMB_DY := 1.2
const FOLLOW_CLIMB_M := 25.0
const FOLLOW_CLIMB_NEAR_M := 3.0
## Beside the lead (m) where a follower climbs up, not onto him (_follow_up_to_lead).
const FOLLOW_CLIMB_SIDE_M := 1.5
const FOLLOW_CLIMB_RETRY_S := 20.0
var _follow_climb := {}
var _follow_climb_retry := -1000.0


func _follow_up_to_lead() -> bool:
	var lead := squad.leader if squad else null
	if lead == null or not is_instance_valid(lead) or lead == body or not lead.vitals.is_up() or not lead.is_on_floor():
		_follow_climb = {}
		return false
	var at := lead.global_position
	var flat := Vector2(at.x - body.global_position.x, at.z - body.global_position.z).length()
	if at.y - body.global_position.y < FOLLOW_CLIMB_DY or flat > FOLLOW_CLIMB_M or Soldier._now() < _follow_climb_retry:
		if not body.movement.mantling:
			_follow_climb = {}
		return body.movement.mantling
	if _follow_climb.is_empty() and not ExoFrame.working(body.inventory):  # (in an LX-3 it leaps up, stairs or not)
		var path := NavigationServer3D.map_get_path(body.get_world_3d().navigation_map, body.global_position, at, true)
		if not path.is_empty() and absf(path[path.size() - 1].y - at.y) < 1.0 and Vector2(path[path.size() - 1].x - at.x, path[path.size() - 1].z - at.z).length() < 3.0:
			return false  # stairs or a ramp up there: the usual follow walks it
	# Not onto the lead himself: his capsule stands on the landing, so the mantle never starts. A
	# spot FOLLOW_CLIMB_SIDE_M beside him along the edge (left or right by squad slot).
	var toward := Vector3(at.x - body.global_position.x, 0.0, at.z - body.global_position.z)
	var side := toward.normalized().cross(Vector3.UP) * (FOLLOW_CLIMB_SIDE_M if body.squad_slot % 2 == 0 else -FOLLOW_CLIMB_SIDE_M)
	var spot := at + side
	if _follow_climb.is_empty():
		_follow_climb = {"point": spot}
	_follow_climb.point = spot
	var r := _climb_toward(_follow_climb, FOLLOW_CLIMB_NEAR_M)
	if r == CLIMB_CANT:
		_follow_climb_retry = Soldier._now() + FOLLOW_CLIMB_RETRY_S
	if r != CLIMB_GOING:
		_follow_climb = {}
		return false
	return true


## Host: "Drop packs here": the worn pack goes on the ground in front, still loaded, and this
## unit remembers which item it is (its uid), not just the model: squadmates often wear the
## same pack with different things in it. False if it wears none (or is busy carrying someone).
func drop_pack() -> bool:
	if body.carrying != null or body.inventory.slots.get(&"backpack", &"") == &"":
		return false
	var entry := body.inventory.unequip(&"backpack")
	if entry.is_empty():
		return false
	var pos := body.global_position - body.global_basis.z * 0.6 + Vector3.UP * 0.4
	var uid := CompoundLevel.current(body).server_spawn_dropped(entry.id, 1, pos, entry.get("state", {}))
	dropped_pack = {"id": entry.id, "uid": uid, "pos": pos}
	return true


## "Pick packs up": back to the pack it dropped, wherever it has rolled since, and on with it
## (if it's still there and no other pack has been put on since). Only its own: another pack
## of the same model lying closer is somebody else's. Gone (someone took it): the order ends.
func _tactic_pick_pack() -> void:
	var own := _dropped_pack_item()
	if own == null or body.inventory.slots.get(&"backpack", &"") != &"":
		dropped_pack = {}
		ordered = {}
		return
	if _flat_distance(own.global_position) > 1.5:
		_go(own.global_position, true)
		return
	_has_destination = false
	if body.inventory.take(own.item_id, 1, own.state) > 0:
		body.model.server_pick_up(own.global_position, own.item_id)
		GameState.item_taken(own.uid)
		own.queue_free()
	dropped_pack = {}
	ordered = {}  # back to what they were doing


## "Climb into the HX-1" (Squad.order_exo_in): to the suit with uid "uid", then in
## (ExoMech.server_enter, its own release-and-zip clip). Gone, taken, or he can't now (the
## suit's own rules): the order ends. He holds still from the release until he's in (the suit
## lets him go if he moves off), and the order ends once he's in.
func _tactic_exo_in(t: Dictionary) -> void:
	if ExoMech.piloting(body.inventory) and not ExoMech.transitioning(body):
		ordered = {}  # in
		return
	if t.has("entering"):
		_stop()  # still: the suit lets him go if he moves off mid-release
		if not ExoMech.transitioning(body) and Soldier._now() > float(t.entering) + ExoMech.RELEASE_S + 1.0:
			ordered = {}  # the climb-in didn't take
		return
	var suit := _world_item(String(t.get("uid", "")))
	if suit == null or ExoMech.enter_problem(body, suit, false) != "":
		ordered = {}
		return
	var at := ExoMech.parked_point(suit)
	var feet := ExoMech.parked_feet(suit)
	var back := Vector3(at.x - feet.x, 0.0, at.z - feet.z)
	var stand := feet + (back.normalized() if back.length() > 0.05 else suit.global_basis.z) * EXO_STAND_M  # behind it, at the release
	if _flat_distance(stand) > EXO_SNAP_M:
		_go(stand, true)
		return
	_stop()
	body.server_place(stand, suit.global_rotation.y)  # the last step onto the spot a player stands at, facing its back
	t["entering"] = Soldier._now()
	ExoMech.server_enter(body, suit)


## The very pack this unit dropped (dropped_pack's uid), lying in the world; null once it's gone.
func _dropped_pack_item() -> WorldItem:
	return _world_item(String(dropped_pack.get("uid", "")))


## The world item with `uid`, not being freed; null if there's none.
func _world_item(uid: String) -> WorldItem:
	if uid == "":
		return null
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var item := node as WorldItem
		if item and item.uid == uid and not item.is_queued_for_deletion():
			return item
	return null


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


## Breaching (Captain, 2026-10-16: "actually stacking before entry", "add one for breach charges";
## "they are for making a door"): the op's "breach" goes in before the stack does: "flash" or
## "frag" thrown BREACH_INSIDE_M through the doorway; "charge" set on the wall beside the stack,
## CHARGE_ALONG_M from the doorway, blowing a way in of its own (Charges' carve). Returns how long
## the stack waits for it (0: this man has nothing to breach with; they go in quiet).
const BREACH_ITEMS := {"flash": &"flashbang", "frag": &"frag_grenade", "charge": &"breaching_charge"}
const BREACH_WAIT_S := {"flash": 1.6, "frag": 2.5}
const BREACH_INSIDE_M := 2.5
const CHARGE_ALONG_M := 2.0


func _breach(op: Dictionary) -> float:
	var how := String(op.get("breach", ""))
	var item: StringName = BREACH_ITEMS.get(how, &"")
	if item == &"" or not Vitals.has_item(body.inventory, item):
		return 0.0
	var door: Vector3 = op.entrance.door
	var normal: Vector3 = op.entrance.normal
	if how == "charge":
		var charges := Charges.of(body)
		if charges == null:
			return 0.0
		var along := Vector3((op.stack[0] as Vector3).x - door.x, 0.0, (op.stack[0] as Vector3).z - door.z)
		along = along.normalized() if along.length() > 0.05 else normal.cross(Vector3.UP)
		var at := door + along * CHARGE_ALONG_M + Vector3.UP * 1.0 + normal * Charges.SURFACE_OFFSET_M
		charges.server_place_at(body, Transform3D(Basis.looking_at(-normal, Vector3.UP), at))
		op.entrance.door = door + along * CHARGE_ALONG_M  # in through the new hole
		return MissionRegistry.setting_f("charge_fuse_s", 10.0) + 0.8
	if order_throw(item, door - normal * BREACH_INSIDE_M + Vector3.UP * 0.5):
		return float(BREACH_WAIT_S.get(how, 2.0))
	return 0.0


## The breach this unit's team would choose itself against a building the enemy holds (Captain:
## "ai may prefer to if enemies are holed up"): a charge if anyone carries one, then a flashbang,
## then a frag; "" for none.
static func preferred_breach(units: Array) -> String:
	for how: String in ["charge", "flash", "frag"]:
		for ai: SquadAI in units:
			if Vitals.has_item(ai.body.inventory, BREACH_ITEMS[how]):
				return how
	return ""


## How far inside the doorway each man steps before his corner (the threshold).
const DOORWAY_STEP_M := 0.9


## Clearing (SquadTactics.clear_op): to this unit's place in the stack, wait for the rest (or
## STACK_WAIT_S), then in one after the other ENTRY_GAP_S apart, each to its room corner; then
## floor by floor (F-01): once everyone has his corner on this floor (or FLOOR_WAIT_S after the
## first did), up the stair one after the other, ENTRY_GAP_S apart, to his corner on the next.
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
		body.want_crouch = true  # low in the stack
		if (op.ready as Dictionary).size() >= int(op.units) or now - float(op.first_ready_at) >= SquadTactics.STACK_WAIT_S:
			var wait := 0.0
			if String(op.get("breach", "")) != "" and not op.get("breached", false):
				op.breached = true
				wait = _breach(op)
			op.go_at = now + wait
			_callout(&"tactic", "Breaching!" if wait > 0.0 else "Going in!")
		return
	if now < float(op.go_at) + slot * SquadTactics.ENTRY_GAP_S:
		_has_destination = false
		_face(door)
		return
	var floors: Array = op.get("floors", [op.rooms])
	var level: int = (op.get("floor_of", {}) as Dictionary).get(slot, 0)
	var corner: Vector3 = floors[level][slot]
	# Through the doorway first (Captain, 2026-10-16: CQB): on the ground floor each man goes in
	# by the threshold, a step inside, then hooks or crosses to his corner, instead of cutting
	# the wall line to it.
	var through: Dictionary = op.get("through", {})
	op["through"] = through
	if level == 0 and not through.has(slot):
		var inside: Vector3 = (op.entrance.door as Vector3) - (op.entrance.normal as Vector3) * DOORWAY_STEP_M
		if _flat_distance(inside) > ARRIVE + 0.2 and _flat_distance(corner) > _flat_between(inside, corner):
			_go(inside, true)
			return
		through[slot] = true
	if _flat_distance(corner) > ARRIVE + 0.3:
		_go(corner, true)
		return
	_has_destination = false
	if not (op.get("cleared", {}) as Dictionary).has("%d/%d" % [level, slot]) and not in_contact():
		var cleared: Dictionary = op.get("cleared", {})
		op["cleared"] = cleared
		cleared["%d/%d" % [level, slot]] = true
		_callout(&"clear", "Clear!")  # his corner, nobody there (voiced: audio/callouts clear_*)
	# His sector (Captain, 2026-10-16: breaching, entry): from his corner, into the room past
	# the middle of where the team's corners are, weapon up.
	var mid := Vector3.ZERO
	for p: Vector3 in floors[level]:
		mid += p
	mid /= maxf((floors[level] as Array).size(), 1.0)
	_face(corner + (mid - corner) * 2.0)
	body.want_aim = true
	if level + 1 < floors.size():
		# This floor done: up the stair once the rest are done here too, one after the other.
		var marks: Dictionary = op.floor_done[level]
		marks[slot] = true
		op.floor_first[level] = minf(float(op.floor_first[level]), now)
		if not is_finite(float(op.floor_go[level + 1])) and (marks.size() >= int(op.units) or now - float(op.floor_first[level]) >= SquadTactics.FLOOR_WAIT_S):
			op.floor_go[level + 1] = now
			_callout(&"tactic", "Clear! Moving up!")
		if is_finite(float(op.floor_go[level + 1])) and now >= float(op.floor_go[level + 1]) + slot * SquadTactics.ENTRY_GAP_S:
			op.floor_of[slot] = level + 1
		return
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
		&"climb":
			return "Climbing" if body.movement.mantling else "Going to climb"
		&"search":
			return "Searching"
		&"give_ammo":
			return "Bringing ammo"
		&"pick_pack":
			return "Getting the pack"
		&"exo_in":
			return "Getting into the HX-1"
	return "Following"


# --- Perception -----------------------------------------------------------

func _find_target() -> Soldier:
	if body.stunned_s > 0.0:
		return null
	if focus != null and (not is_instance_valid(focus) or focus.is_queued_for_deletion() or not focus.vitals.is_up() \
			or not focus.is_in_group(&"combatants")):
		focus = null  # the target is down (or a dead player waiting to respawn, Soldier): pick freely again
	if focus != null and focus.faction != body.faction and not Person.is_noncombatant(focus) \
			and body.global_position.distance_to(focus.global_position) <= Squad.TARGET_RANGE and can_see(focus) \
			and Spotting.foliage_m(_zone_scatter(), body, focus) < Spotting.FOLIAGE_OPAQUE_M:
		return focus  # (deep in the leaves he's lost even when ordered: the search below takes over)
	var best: Soldier = null
	var best_dist := reach_m(body)  # (was SQUAD_SIGHT_RANGE / SIGHT_RANGE for all, 300 m)
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
			# Unconscious foes are left alone, except for a dead-check while clearing (once
			# each: a body he has checked counts as dead to him).
			if clearing and d < check_dist and not _dead_check_done(s) and can_see(s):
				check = s
				check_dist = d
			continue
		_checked.erase(s.get_instance_id())  # up again (revived): he can be checked again if he goes down
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
		if check != _dead_check:
			_dead_check_rounds = 0
			_dead_check_since = Soldier._now()
		_dead_check = check
	elif _dead_check != null and not _dead_check_valid(_dead_check):
		_dead_check = null
	return best if best != null else _dead_check


## How many rounds the next burst is (G-09): by the weapon, the range, whether it's a point being
## suppressed rather than a man, and doctrine `doctrine`'s burst factor.
static func burst_rounds(weapon: ItemData, range_m: float, suppressing: bool, doctrine: StringName) -> int:
	var auto: bool = weapon.stats.get("auto", false)
	var band := Vector2i(1, 1)
	if weapon.tags.has("lmg") or weapon.tags.has("hmg"):
		band = Vector2i(4, 7) if range_m < BURST_FAR_M else Vector2i(3, 6)  # a gun's job is volume
	elif suppressing:
		band = Vector2i(2, 4) if auto else Vector2i(1, 3)
	elif range_m < BURST_CLOSE_M:
		band = Vector2i(3, 5) if auto else Vector2i(2, 3)
	elif range_m < BURST_FAR_M:
		band = Vector2i(2, 3) if auto else Vector2i(1, 2)
	var n := randi_range(band.x, band.y)
	if band.y > 1:
		n = roundi(n * Doctrine.value(doctrine, "burst"))
	return maxi(n, 1)


## The pause after a burst, as a factor (G-09): longer the further out, and doctrine's burst_pause.
static func pause_mult(range_m: float, doctrine: StringName) -> float:
	return minf(1.0 + maxf(range_m - BURST_CLOSE_M, 0.0) * PAUSE_PER_M, PAUSE_MAX_MULT) * Doctrine.value(doctrine, "burst_pause")


## This unit's doctrine id: its squad's, else its side's (Doctrine.default_for).
func _doctrine_id() -> StringName:
	if squad and squad.doctrine != &"":
		return squad.doctrine
	return Doctrine.default_for(body.faction)


## The stance this unit takes on its own in a fight (G-05): SoldierMovement.Stance.PRONE, or -1
## to leave it to the crouch logic (see PRONE_MIN_M).
func _auto_stance() -> int:
	if not body.vitals.is_up() or body.carrying != null or Vehicle.ride_of(body) != null or body.inventory.hands != &"":
		return -1
	var pinned := body.suppression >= PINNED
	if _has_destination and not pinned:
		return -1  # on the move: on his feet (a pinned man crawls)
	var foe: Soldier = target if target != null and is_instance_valid(target) and target.vitals.is_up() else null
	var threat := foe.global_position if foe else body.threat_pos
	if threat == Vector3.ZERO or body.global_position.distance_to(threat) < PRONE_MIN_M:
		return -1  # close in: on his knees or feet, ready to move
	if pinned and not _at_cover():
		return SoldierMovement.Stance.PRONE  # pinned in the open: flat, now
	var now := Soldier._now()
	if now - _stance_at < STANCE_CHECK_S:
		return SoldierMovement.Stance.PRONE if _auto_prone else -1
	_stance_at = now
	if foe == null:
		return SoldierMovement.Stance.PRONE if _auto_prone and in_contact() else -1  # keeps it while the fight lasts
	var world := body.get_world_3d()
	if not Throwables.clear_line(world, body.global_position + Vector3.UP * PRONE_EYE_M, foe.aim_point()):
		return -1  # lying there he can't see him: kneel or stand to fire
	var hidden := not Throwables.clear_line(world, threat + Vector3.UP * 1.5, body.global_position + Vector3.UP * FOLD_HIDDEN_M)
	if hidden or body.global_position.distance_to(threat) >= PRONE_OPEN_M:
		return SoldierMovement.Stance.PRONE
	return -1


## Whether `q` is a fold in the ground against the threat (G-17): lying there he's hidden
## (FOLD_HIDDEN_M) and from his prone eye (PRONE_EYE_M) he sees over it.
func _fold_at(world: World3D, q: Vector3) -> bool:
	var from := body.threat_pos + Vector3.UP * 1.5
	return not Throwables.clear_line(world, from, q + Vector3.UP * FOLD_HIDDEN_M) \
		and Throwables.clear_line(world, q + Vector3.UP * PRONE_EYE_M, body.threat_pos + Vector3.UP * 1.2)


## How far out `s` picks targets with the weapon in hand (G-27; see REACH_IRONS_M).
static func reach_m(s: Soldier) -> float:
	var weapon := s.active_weapon() if s.inventory else null
	if weapon == null or weapon.type != "weapon":
		return REACH_IRONS_M
	if String(weapon.stats.get("sound", "")) == "pistol":
		return REACH_PISTOL_M
	var optic := GunSight.optic_of(s)
	var power := float(optic.stats.get("magnification_max", optic.stats.get("magnification", 1.0))) if optic else 1.0
	return minf(REACH_IRONS_M * (1.0 + REACH_PER_POWER * maxf(power - 1.0, 0.0)), REACH_MAX_M)


## One scan's worth of spotting `s` (in sight, `leaves` metres of foliage in the way):
## awareness rises by SCAN_S over the time Spotting gives. Returns the new awareness.
func _build_awareness(s: Soldier, leaves := 0.0) -> float:
	var id := s.get_instance_id()
	var a: float = _aware.get(id, 0.0)
	if a < 1.0:
		if _preset == "":
			_preset = Spotting.preset_of(body)
		var suppressed := body.suppression >= SUPPRESSED
		var t := Spotting.spot_seconds(body, s, _preset, _react_combat(), suppressed, Soldier._now(), leaves, not in_contact() and not suppressed)
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


## Still worth dead-checking: unconscious (not dead), within DEAD_CHECK_M and not checked yet.
## Kept while it drops in and out of sight behind low cover: only death, distance or the check
## being done (_dead_check_done) ends it.
func _dead_check_valid(s: Soldier) -> bool:
	return is_instance_valid(s) and not s.is_queued_for_deletion() and not s.vitals.is_dead() and not s.vitals.is_up() \
		and body.global_position.distance_to(s.global_position) <= DEAD_CHECK_M and not _dead_check_done(s)


## This unit has dead-checked `s` (fired DEAD_CHECK_ROUNDS at him, _start_burst), or has been
## at it past the look plus DEAD_CHECK_GIVE_UP_S without a clean shot (he looked; the body
## counts as dead to him, and is marked checked here).
func _dead_check_done(s: Soldier) -> bool:
	var id := s.get_instance_id()
	if _checked.has(id):
		return true
	if s == _dead_check and Soldier._now() - _dead_check_since > lerpf(DEAD_CHECK_LOOK_UNSKILLED_S, DEAD_CHECK_LOOK_SKILLED_S, combat) + DEAD_CHECK_GIVE_UP_S:
		_checked[id] = true
		return true
	return false


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
	var taken := _covers_taken()  # (once a search, not once a candidate: perf, in-fight AI)
	for ring in COVER_RINGS:
		if ring > leash + 0.1:
			break
		for k in 12:
			var angle := TAU * k / 12.0 + ring
			var p := anchor + Vector3(cos(angle), 0.0, sin(angle)) * ring
			var q := NavigationServer3D.map_get_closest_point(map, p)
			if Vector2(q.x - p.x, q.z - p.z).length() > 0.6:
				continue
			var score := _flat_distance(q) + q.distance_to(anchor) * 0.5
			if score - COVER_LOW_BONUS >= best_score:
				continue  # it can't win even as the best low cover: skip its raycasts and voxel trace
			if taken.any(func(c: Vector3) -> bool: return c.distance_to(q) < COVER_GAP_M):
				continue
			if not _cover_protects(q):
				if q.distance_to(body.threat_pos) < PRONE_MIN_M or not _fold_at(world, q):
					continue
				score -= FOLD_BONUS  # a fold in the ground: prone behind it, firing over (G-17, G-05)
			else:
				if not VoxelWorld.stops_round_in(body, body.threat_pos + Vector3.UP * 1.5, q + Vector3.UP * 0.9, SOFT_COVER_TEST_J):
					score += SOFT_COVER_PENALTY  # only wood or sheet metal in the way: rounds come through
				if Throwables.clear_line(world, q + Vector3.UP * 1.6, body.threat_pos + Vector3.UP * 1.2):
					score -= COVER_LOW_BONUS  # low cover: you can stand up and return fire
			score += maxf(0.0, 6.0 - q.distance_to(body.threat_pos)) * 2.0
			if score < best_score:
				best = q
				best_score = score
	return best


## Where to drag a casualty to (Captain, 2026-10-17: they "drag illogical ways"): not a firing
## position (find_cover likes low cover you can shoot over, and doesn't mind the way there) but
## the nearest spot that hides someone lying down from the threat, away from it rather than
## toward it or across its line, with the way there clear enough to drag along.
func find_drag_cover(anchor: Vector3, leash: float) -> Variant:
	var map := body.get_world_3d().navigation_map
	var world := body.get_world_3d()
	var to_threat := body.threat_pos - anchor
	to_threat.y = 0.0
	to_threat = to_threat.normalized() if to_threat.length() > 0.1 else Vector3.ZERO
	var best: Variant = null
	var best_score := INF
	for ring in COVER_RINGS:
		if ring > leash + 0.1:
			break
		for k in 12:
			var angle := TAU * k / 12.0 + ring
			var p := anchor + Vector3(cos(angle), 0.0, sin(angle)) * ring
			var q := NavigationServer3D.map_get_closest_point(map, p)
			if Vector2(q.x - p.x, q.z - p.z).length() > 0.6 or _cover_taken(q):
				continue
			if Throwables.clear_line(world, body.threat_pos + Vector3.UP * 1.5, q + Vector3.UP * 0.35):
				continue  # someone lying there is still in its sight
			var way := q - anchor
			way.y = 0.0
			var path := NavigationServer3D.map_get_path(map, anchor, q, true)
			var length := 0.0
			for i in range(1, path.size()):
				length += path[i - 1].distance_to(path[i])
			if path.size() < 2 or length > way.length() * 1.6 + 2.0:
				continue  # a long way round (a wall between): not a drag
			var score := length
			if to_threat != Vector3.ZERO and way.length() > 0.1:
				score += maxf(way.normalized().dot(to_threat), 0.0) * 6.0  # toward the shooter: worse
			if score < best_score:
				best = q
				best_score = score
	return best


func _cover_protects(point: Vector3) -> bool:
	if not Throwables.clear_line(body.get_world_3d(), body.threat_pos + Vector3.UP * 1.5, point + Vector3.UP * 0.9):
		return true
	return _auto_prone and point.distance_to(_cover_point) < 0.5 and _fold_at(body.get_world_3d(), point)  # lying behind a fold


## The cover spots other soldiers hold now (find_cover checks its candidates against them).
func _covers_taken() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var other := SquadAI.of(n)
		if other and other != self and other._has_cover:
			out.append(other._cover_point)
	return out


func _cover_taken(point: Vector3) -> bool:
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var other := SquadAI.of(n)
		if other and other != self and other._has_cover and other._cover_point.distance_to(point) < COVER_GAP_M:
			return true
	return false


func _start_drag_watch() -> void:
	_drag_best = INF
	_drag_moved_at = Soldier._now()
	_drag_contact_at = Soldier._now()


## Dragging to cover should stop: no closer to the cover spot for DRAG_STUCK_S, or no contact
## for DRAG_QUIET_S (nothing to drag them out of the line of fire from any more).
func _drag_stalled(contact: bool) -> bool:
	var now := Soldier._now()
	if contact:
		_drag_contact_at = now
	var d := _flat_distance(_cover_point)
	if d < _drag_best - DRAG_PROGRESS_M:
		_drag_best = d
		_drag_moved_at = now
	var stuck := now - _drag_moved_at > DRAG_STUCK_S
	if stuck or now - _drag_contact_at > DRAG_QUIET_S:
		SessionLog.note("%s puts %s down (%s)" % [body.log_name(), _name_of(casualty),
			"no closer to cover for %.0f s" % DRAG_STUCK_S if stuck else "out of contact"])
		return true
	return false


func _at_cover() -> bool:
	return _has_cover and _flat_distance(_cover_point) <= ARRIVE + 0.4


func _buddy_bounding() -> bool:
	var ai := SquadAI.of(buddy) if is_instance_valid(buddy) and buddy.vitals.is_up() else null
	return ai != null and ai.bounding


# --- Shooting -------------------------------------------------------------

## A new target `t` (or the same one gone down or back up): the reaction time before the first
## round, and for one who is up, the first-shot error (_acq_offset, mostly low: the muzzle comes
## up onto him; CQB_HIGH_SHARE high) and the snap-aim hold before a big swing (_acq_hold_s),
## both larger the further the target is off his aim, and the first burst's hold (_new_hold);
## for an unconscious one (a dead-check), a look of DEAD_CHECK_LOOK_*_S instead, no error
## (Captain, P0362). Doctrine's reaction factor (audit A3-07) belongs on `react` here.
func _acquire(t: Soldier) -> void:
	_acq_age = 0.0
	_acq_up = t.vitals.is_up()
	var to := t.aim_point() - body.camera.global_position
	var swing_deg := rad_to_deg((-body.camera.global_basis.z).angle_to(to.normalized())) if to.length() > 0.01 else 0.0
	var react: float
	var react_combat := _react_combat()
	if _acq_up:
		react = lerpf(0.9, 0.25, react_combat)  # reaction time
		_acq_hold_s = lerpf(TURN_HOLD_UNSKILLED_S, TURN_HOLD_SKILLED_S, react_combat) if swing_deg > TURN_HOLD_MIN_DEG else 0.0
		var a := lerpf(CQB_ACQ_UNSKILLED_M, CQB_ACQ_SKILLED_M, combat) * (0.5 + minf(swing_deg, 120.0) / 120.0)
		var up := CQB_HIGH_MULT if randf() < CQB_HIGH_SHARE else -1.0
		_acq_offset = Vector2(a * randf_range(-0.7, 0.7), up * a * randf_range(0.4, 1.0))
		_new_hold()
	else:
		react = lerpf(DEAD_CHECK_LOOK_UNSKILLED_S, DEAD_CHECK_LOOK_SKILLED_S, react_combat)
		_acq_hold_s = 0.0
		_acq_offset = Vector2.ZERO
	_acq_react_s = react
	_next_shot = maxf(_next_shot, Soldier._now() + react)


## Where to aim at `foe` this frame (advances the time since he was acquired by `delta`). A
## downed foe being dead-checked: his belly (_dead_check_point). One who is up: his chest,
## plus, within CQB_FADE_M (fully within CQB_FULL_M), the first-shot error settling away once
## the reaction time has passed and this burst's own small offset; further out (fully from
## CQB_FADE_M), this burst's hold at range (_burst_hold, an angle, so metres grow with range).
func _cqb_aim_point(foe: Soldier, delta: float) -> Vector3:
	_acq_age += delta
	if not foe.vitals.is_up():
		return _dead_check_point(foe)
	var p := foe.aim_point()
	var from := body.camera.global_position
	var dist := from.distance_to(p)
	var w := clampf((CQB_FADE_M - dist) / (CQB_FADE_M - CQB_FULL_M), 0.0, 1.0)
	var off := _burst_hold * dist * (1.0 - w)
	if w > 0.0:
		var settle := lerpf(CQB_SETTLE_UNSKILLED_S, CQB_SETTLE_SKILLED_S, combat)
		off += (_acq_offset * exp(-maxf(_acq_age - _acq_react_s, 0.0) / settle) + _burst_offset) * w
	if off == Vector2.ZERO:
		return p
	var flat := Vector3(p.x - from.x, 0.0, p.z - from.z)
	var right := flat.normalized().cross(Vector3.UP) if flat.length() > 0.01 else body.global_basis.x
	return p + right * off.x + Vector3.UP * off.y


## Turns toward `point` for a shot at `foe` and returns the angle still off (radians), except
## for the first _acq_hold_s after a big swing was called for: he holds still, taking in what
## he saw, and the angle is what it is.
func _aim_for_shot(point: Vector3, foe: Soldier) -> float:
	if foe != null and _acq_age < _acq_hold_s:
		var d := point - body.camera.global_position
		return (-body.camera.global_basis.z).angle_to(d.normalized()) if d.length() > 0.001 else 0.0
	return _aim_at(point)


## May a round go now (the time gates passed)? At a foe who is up, aimed at `point`: where the
## sights cross his range, within GATE_*_M of the point to the side, GATE_HIGH_MULT of that
## above, GATE_LOW_MULT below (_gate_miss_ok). A dead-check: within DEAD_CHECK_GATE_DEG, rounds
## left of DEAD_CHECK_ROUNDS, and the sights on his body rather than his head (_sights_on_body).
## Covering fire at a spot (no foe): within 6 degrees, as ever.
func _gate_open(foe: Soldier, error: float, point: Variant = null) -> bool:
	if foe != null and not foe.vitals.is_up():
		return error <= deg_to_rad(DEAD_CHECK_GATE_DEG) and _dead_check_rounds < DEAD_CHECK_ROUNDS and _sights_on_body(foe)
	if foe == null or point == null:
		return error <= deg_to_rad(6.0)
	return _gate_miss_ok(point)


## Whether the sights (straight down the camera) pass close enough to `point` for a round at a
## foe: measured in metres in the plane square to the line at his range (GATE_* above).
func _gate_miss_ok(point: Vector3) -> bool:
	var from := body.camera.global_position
	var to := point - from
	var dist := to.length()
	if dist < 0.05:
		return true
	var along := to / dist
	var dir := -body.camera.global_basis.z
	var cos_off := dir.dot(along)
	if cos_off <= 0.1:
		return false
	var miss := from + dir * (dist / cos_off) - point
	var up := (Vector3.UP - along * along.y)
	up = up.normalized() if up.length() > 0.01 else body.global_basis.z
	var high := miss.dot(up)
	var side := absf(miss.dot(along.cross(up)))
	var gate := maxf(lerpf(GATE_UNSKILLED_M, GATE_SKILLED_M, combat), dist * tan(deg_to_rad(GATE_MIN_DEG)))
	return side <= gate and high <= gate * GATE_HIGH_MULT and high >= -gate * GATE_LOW_MULT


## The next burst's aim off the chest, drawn when a target is acquired and as each burst ends
## (so the sights settle on it before its first round): a small offset up close (capped on the
## high side) and the hold at range (_burst_hold: wider while he's new to the target).
func _new_hold() -> void:
	_burst_offset = Vector2(randfn(0.0, CQB_BURST_OFFSET_M), minf(randfn(-0.02, 0.04), 0.03))
	var hold := deg_to_rad(lerpf(RANGE_HOLD_UNSKILLED_DEG, RANGE_HOLD_SKILLED_DEG, combat)) \
		* (1.0 + RANGE_ACQ_MULT * exp(-_acq_age / RANGE_SETTLE_S))
	_burst_hold = Vector2(randfn(0.0, hold), randfn(0.0, hold))


## A new burst at `foe`. A dead-check fires one round at a time and counts them; the last one
## marks the body checked.
func _start_burst(foe: Soldier) -> void:
	if foe == null or foe.vitals.is_up():
		return
	_burst_left = 1
	_dead_check_rounds += 1
	if _dead_check_rounds == 1:
		SessionLog.note("%s dead-checks %s at %.0f m" % [body.log_name(), SessionLog.who(foe), body.global_position.distance_to(foe.body_point())])
	if _dead_check_rounds >= DEAD_CHECK_ROUNDS:
		_checked[foe.get_instance_id()] = true


## The middle of `s`'s hitbox for `part` (Vitals.CHEST...), wherever his pose or ragdoll put it;
## null if he has none.
static func _part_point(s: Soldier, part: StringName) -> Variant:
	for child in s.get_children():
		if child is Area3D and child.get_meta(&"body_part", &"") == part:
			for shape in child.get_children():
				if shape is CollisionShape3D:
					return (shape as CollisionShape3D).global_position
	return null


## Where a dead-check aims: the belly (well away from the head), else the chest.
func _dead_check_point(s: Soldier) -> Vector3:
	var p: Variant = _part_point(s, Vitals.ABDOMEN)
	return p if p != null else s.aim_point()


## Whether his sights (straight down the camera) meet `foe`'s body first, not his head, face
## or neck, nor nothing: from a body's head end the head hides the torso, and a dead-check
## round goes only where it meets the torso or limbs. Geometric, against the hitbox boxes.
func _sights_on_body(foe: Soldier) -> bool:
	var from := body.camera.global_position
	var dir := -body.camera.global_basis.z
	var nearest := INF
	var part: StringName = &""
	for child in foe.get_children():
		if not (child is Area3D and child.has_meta(&"body_part")):
			continue
		for shape in child.get_children():
			var cs := shape as CollisionShape3D
			if cs == null or not (cs.shape is BoxShape3D):
				continue
			var xf := cs.global_transform
			var inv := xf.affine_inverse()
			var size := (cs.shape as BoxShape3D).size
			var hit: Variant = AABB(-size * 0.5, size).intersects_ray(inv * from, inv.basis * dir)
			if hit == null:
				continue
			var dist := from.distance_to(xf * (hit as Vector3))
			if dist < nearest:
				nearest = dist
				part = child.get_meta(&"body_part")
	return part != &"" and part not in [Vitals.HEAD, Vitals.FACE, Vitals.NECK]


func _shoot() -> void:
	var tla := Time.get_ticks_usec()
	var launched := LauncherAI.think(self)
	_p(&"shoot_launcher", tla)
	if launched:
		return  # the launcher has them: vehicles, a group behind cover, an order (wave 5)
	var now := Soldier._now()
	var weapon := body.active_weapon()
	if weapon == null or weapon.type != "weapon" or body.carrying != null or body.is_reloading \
			or body.stunned_s > 0.0 or (body.suppression >= PINNED and not _suppressing) or not weapons_free():
		return
	var foe := _foe()
	var aim_at: Variant = null
	var tactic_fire := false  # a base of fire's or a Suppress order's point
	if foe != null:
		aim_at = _cqb_aim_point(foe, get_physics_process_delta_time())
	elif _suppressing:
		aim_at = body.threat_pos + Vector3.UP * 1.0  # keep their heads down before going out to the casualty
	elif _suppress_point() != null:
		aim_at = _suppress_point()
		tactic_fire = true
	elif intent != Intent.CASUALTY and (_buddy_bounding() or _cover_medic) and in_contact() and now - _last_contact < 5.0:
		aim_at = body.threat_pos + Vector3.UP * 1.0  # covering fire while the buddy (or a medic) moves
	elif intent == Intent.FIGHT:
		_maybe_frag()
	if aim_at == null:
		_no_shot_since = -1.0
		return
	var far := body.camera.global_position.distance_to(aim_at)
	if far > HOLDOVER_FROM_M:
		aim_at += Vector3.UP * Ballistics.drop_m(weapon, far) * (0.8 + 0.2 * combat)  # held over, a little short when green (G-27)
	var error := _aim_for_shot(aim_at, foe)
	if body.want_crouch and _at_cover() and foe != null:
		body.want_crouch = false  # stand up to shoot over cover
		return
	if now < _next_shot or now < _pause_until or now < body._busy_until or not _gate_open(foe, error, aim_at):
		return
	# Nothing of the world in the way (v0.4.6: rounds went into the compound wall in front of them).
	var tl := Time.get_ticks_usec()
	var line := _fire_line_state(aim_at, foe)
	_p(&"shoot_fire_line", tl)
	if line != FireLine.CLEAR:
		if line == FireLine.STAND:
			body.want_crouch = false  # on his feet the line is clear: up to fire over it
		if _no_shot_since < 0.0:
			_no_shot_since = now
		if tactic_fire and now - _no_shot_since >= NO_SHOT_MOVE_S and now - _fire_spot_at >= FIRE_SPOT_RETRY_S:
			_seek_fire_spot()
		return
	_no_shot_since = -1.0
	if body.inventory.rounds_in(body.active_slot) <= 0 or _friendly_in_line(aim_at):
		return
	var auto: bool = weapon.stats.get("auto", false)
	_next_shot = now + 60.0 / float(weapon.stats.get("rpm", 600)) * (1.0 if auto else 1.6)
	var range_m := body.camera.global_position.distance_to(aim_at)
	if _burst_left <= 0:
		_burst_left = burst_rounds(weapon, range_m, foe == null, _doctrine_id())
		_suppress_jitter = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.5), randf_range(-1, 1)) * SUPPRESS_SPREAD_M
		_start_burst(foe)  # (a dead-check: one deliberate round at a time)
	_burst_left -= 1
	if _burst_left <= 0:
		_new_hold()  # the next burst's aim (the sights settle on it in the pause)
		_pause_until = now + randf_range(0.5, 1.1) / lerpf(0.7, 1.3, combat) * pause_mult(range_m, _doctrine_id())
	var dir := body.ai_spread_direction(weapon)  # the AI keeps its own cone (Captain, P0362)
	var extra := deg_to_rad(_aim_error_deg(foe != null))
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * tan(extra) * 0.6).normalized()
	var tf := Time.get_ticks_usec()
	body._server_fire.rpc_id(1, body.camera.global_position, dir, body.active_slot)
	_p(&"shoot_fire_round", tf)


## Whether a round from here would get to `aim` (FireLine.CLEAR), would only from his feet while
## he's crouched (STAND), or wouldn't (BLOCKED): the world may stop it up to FIRE_LINE_SLACK_M
## short of a point, FIRE_LINE_FOE_SLACK_M short of a foe who is up (his aim point, not the
## burst's hold off it) or 1 m short of one lying down (_fire_line_from). Kept for
## FIRE_LINE_CACHE_S while he and the aim stay put.
func _fire_line_state(aim: Vector3, foe: Soldier) -> FireLine:
	var from := body.camera.global_position
	if foe != null and foe.vitals.is_up():
		aim = foe.aim_point()  # the man himself: a burst's hold low into the cover in front of him is a fair miss
	var now := Soldier._now()
	var c := _fire_line
	if not c.is_empty() and now - float(c.at) < FIRE_LINE_CACHE_S and (c.from as Vector3).distance_to(from) < 0.3 \
			and (c.to as Vector3).distance_to(aim) < 1.0 and bool(c.foe) == (foe != null):
		return c.state
	# A foe lying down: the ground round him isn't a wall (a dead-check aims at his belly).
	var slack := FIRE_LINE_SLACK_M if foe == null else (FIRE_LINE_FOE_SLACK_M if foe.vitals.is_up() else 1.0)
	var state := FireLine.CLEAR
	if not _fire_line_from(from, aim, slack):
		state = FireLine.BLOCKED
		var feet := body.global_position + Vector3.UP * FIRE_EYE_STAND_M
		if from.y < feet.y - 0.25 and _fire_line_from(feet, aim, slack):
			state = FireLine.STAND
	_fire_line = {"at": now, "from": from, "to": aim, "foe": foe != null, "state": state}
	return state


## Whether a round of the weapon in hand fired from `from` at `to` gets to within `slack` metres
## of it: nothing of the world in the way, or only what it goes through with the energy it has
## at that range (wood, sheet metal: VoxelWorld.stops_round_in), never concrete or the ground.
func _fire_line_from(from: Vector3, to: Vector3, slack: float) -> bool:
	var d := from.distance_to(to)
	if d <= slack + 0.05:
		return true
	var end := from.lerp(to, (d - slack) / d)
	var weapon := body.active_weapon()
	if weapon == null or weapon.type != "weapon":
		return Throwables.clear_line(body.get_world_3d(), from, end)
	return not VoxelWorld.stops_round_in(body, from, end, Ballistics.world_energy(weapon, d))


## A base of fire (or a Suppress order) that has had no line of fire for NO_SHOT_MOVE_S: a fire
## position to move to (_find_fire_spot), or, with none, it holds and says so. A "[tactics]" line either way.
func _seek_fire_spot() -> void:
	_fire_spot_at = Soldier._now()
	var aim: Vector3 = _tactic().get("aim", Vector3.INF)
	if not aim.is_finite():
		return
	var found: Variant = _find_fire_spot(aim)
	if found == null:
		_fire_spot = null
		print("[tactics] %s: no line of fire on (%.0f, %.0f) and no fire position within %.0f m: holds fire" % [body.name, aim.x, aim.z, FIRE_SPOT_RINGS[-1]])
		_callout(&"no_shot")
		return
	_fire_spot = found.spot
	_fire_spot_aim = aim
	_fire_spot_stand = found.stand
	print("[tactics] %s: no line of fire on (%.0f, %.0f) from here: moves %.0f m to a fire position at (%.0f, %.0f), %s" % [body.name,
		aim.x, aim.z, found.walk, found.spot.x, found.spot.z, "standing" if found.stand else "crouched"])


## The spot on the navmesh round him (FIRE_SPOT_RINGS) with a line of fire to `aim` from a crouch,
## else on his feet, that is the shortest walk (at most FIRE_SPOT_PATH_M), one in cover from the
## aim and a crouch preferred; none another squadmate holds. {"spot", "stand", "walk"} or null.
func _find_fire_spot(aim: Vector3) -> Variant:
	var world := body.get_world_3d()
	var map := world.navigation_map
	var here := body.global_position
	# The baked mesh sits above the ground (by what it does under his feet): eyes go from the ground.
	var lift := NavigationServer3D.map_get_closest_point(map, here).y - here.y
	var found: Array[Dictionary] = []
	for ring in FIRE_SPOT_RINGS:
		for k in 12:
			var angle := TAU * k / 12.0 + ring
			var p := here + Vector3(cos(angle), 0.0, sin(angle)) * ring
			var q := NavigationServer3D.map_get_closest_point(map, p)
			if Vector2(q.x - p.x, q.z - p.z).length() > 0.8 or _fire_spot_taken(q):
				continue
			var stand := false
			var ground := q + Vector3.DOWN * clampf(lift, 0.0, 1.0)
			if not _fire_line_from(ground + Vector3.UP * FIRE_EYE_CROUCH_M, aim, FIRE_LINE_SLACK_M):
				if not _fire_line_from(ground + Vector3.UP * FIRE_EYE_STAND_M, aim, FIRE_LINE_SLACK_M):
					continue
				stand = true
			var extra := 3.0 if stand else 0.0
			if Throwables.clear_line(world, aim, ground + Vector3.UP * 0.6):
				extra += 6.0  # nothing between him and them even down low
			found.append({"spot": q, "stand": stand, "extra": extra, "score": _flat_distance(q) + extra})
	# The likeliest few by the flat distance, then by the walk there (round a wall, out a gate).
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) < float(b.score))
	var best: Variant = null
	for c in found.slice(0, 12):
		var path := NavigationServer3D.map_get_path(map, here, c.spot, true)
		if path.is_empty() or _flat_between(path[path.size() - 1], c.spot) > 0.8:
			continue
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		c.walk = length
		c.score = length + float(c.extra)
		if length <= FIRE_SPOT_PATH_M and (best == null or float(c.score) < float(best.score)):
			best = c
	return best


## Someone else holds `point` (his cover, his fire position, or he stands there).
func _fire_spot_taken(point: Vector3) -> bool:
	if _cover_taken(point):
		return true
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s == body or not s.vitals.is_up():
			continue
		if _flat_between(s.global_position, point) < 1.0:
			return true
		var other := SquadAI.of(s)
		if other and other._fire_spot != null and _flat_between(other._fire_spot, point) < COVER_GAP_M:
			return true
	return false


## A base of fire or Suppress unit with a fire position (_seek_fire_spot) goes there and fires from
## it while it suppresses; the spot goes when the tactic or its aim does. Other intents (care,
## reloading, a moving tactic), a foe in sight or being pinned leave it be for now.
func _keep_to_fire_spot() -> void:
	if _fire_spot == null:
		_take_overwatch()
	if _fire_spot == null:
		return
	var aim: Vector3 = _tactic().get("aim", Vector3.INF)
	var kind := StringName(_tactic().get("kind", &""))
	if (kind != &"base" and kind != &"suppress") or not aim.is_finite() or aim.distance_to(_fire_spot_aim) > FIRE_SPOT_AIM_M:
		_fire_spot = null
		return
	if intent not in [Intent.FOLLOW, Intent.HOLD, Intent.FIGHT] or _suppress_point() == null or _foe() != null \
			or body.suppression >= PINNED or body.stunned_s > 0.0:
		return
	var spot: Vector3 = _fire_spot
	if _flat_distance(spot) > ARRIVE + 0.2:
		_go(spot, true)
	else:
		_has_destination = false
		body.want_crouch = not _fire_spot_stand


## A base of fire whose plan found it high ground (SquadTactics.overwatch_spot, G-17) takes it
## as its fire position, each man a few metres apart round it. A friendly holding on an order
## stays where he was put.
func _take_overwatch() -> void:
	var t := _tactic()
	var spot: Variant = t.get("spot")
	if StringName(t.get("kind", &"")) != &"base" or not (spot is Vector3) or (_friendly() and order != Squad.Order.FOLLOW):
		return
	var aim: Vector3 = t.get("aim", Vector3.INF)
	if not aim.is_finite() or (_overwatch_taken is Vector3 and (_overwatch_taken as Vector3).distance_to(spot) < 1.0):
		return  # this one's been given already (he got there, or gave it up)
	_overwatch_taken = spot
	var map := body.get_world_3d().navigation_map
	var turn := absi(String(body.name).hash()) % 8
	for i in 8:
		var angle := TAU * float((turn + i) % 8) / 8.0
		var q := NavigationServer3D.map_get_closest_point(map, (spot as Vector3) + Vector3(cos(angle), 0.0, sin(angle)) * OVERWATCH_SPREAD_M)
		if _fire_spot_taken(q) or not _fire_line_from(q + Vector3.UP * FIRE_EYE_STAND_M, aim, FIRE_LINE_SLACK_M):
			continue
		_fire_spot = q
		_fire_spot_aim = aim
		_fire_spot_stand = not _fire_line_from(q + Vector3.UP * FIRE_EYE_CROUCH_M, aim, FIRE_LINE_SLACK_M)
		print("[tactics] %s: base of fire to high ground at (%.0f, %.0f), %.0f m up on the enemy" % [body.name, q.x, q.z, q.y - aim.y])
		return


## Status words for a unit with a mark and no line of fire (_shoot), or "" for none.
func _no_shot_text() -> String:
	if body == null or intent not in [Intent.FOLLOW, Intent.HOLD, Intent.FIGHT] or body.stunned_s > 0.0 or body.suppression >= PINNED:
		return ""
	if _fire_spot != null and _has_destination and _destination == _fire_spot:
		return "Moving to a fire position"
	if _no_shot_since >= 0.0 and Soldier._now() - _no_shot_since >= NO_SHOT_MOVE_S:
		return "No shot"
	return ""


## The aim error (degrees) this unit adds to its weapon's own spread: less skill, suppression,
## firing at a point rather than a seen foe, and shaken morale all widen it.
func _aim_error_deg(seen_foe: bool) -> float:
	var shaken := maxf(MORALE_SHAKEN - morale, 0.0) / MORALE_SHAKEN  # 0 steady .. 1 no morale left
	return (1.0 - combat) * AIM_UNSKILLED_DEG + body.suppression * 4.0 + (0.0 if seen_foe else 3.0) + shaken * MORALE_SHAKEN_AIM_DEG


## The half-angle (radians) this unit's next rounds may stray by: the weapon's spread plus
## its aim error (_aim_error_deg).
func _fire_cone() -> float:
	var weapon := body.active_weapon()
	var spread := Soldier.ai_spread_deg(weapon) if weapon else 1.0
	return deg_to_rad(spread + _aim_error_deg(_foe() != null))


## Turns the body and head toward a point; returns the remaining angle in radians.
func _aim_at(point: Vector3) -> float:
	var from := body.camera.global_position
	var d := point - from
	var flat := Vector2(d.x, d.z)
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, flat.length())
	var dt := get_physics_process_delta_time()
	var step := 1.0 - exp(-TURN_RATE * lerpf(0.6, 1.4, combat) * dt)
	# The same ease as ever, but no faster than the swing cap (Captain, P0362): a snap round to
	# a man behind him takes its time.
	var cap := deg_to_rad(lerpf(SWING_UNSKILLED_DEG_S, SWING_SKILLED_DEG_S, combat)) * dt
	body.rotation.y += clampf(wrapf(yaw - body.rotation.y, -PI, PI) * step, -cap, cap)
	var cap_pitch := cap * PITCH_SWING_MULT
	body.head.rotation.x += clampf((clampf(pitch, -1.4, 1.4) - body.head.rotation.x) * step, -cap_pitch, cap_pitch)
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
		var off := closest[0].distance_to(closest[1])
		if along < MUZZLE_M and off > MUZZLE_BODY_M:
			continue  # beside or behind the muzzle, clear of his body
		var clearance := FRIENDLY_CLEARANCE + along * widen + (LYING_EXTRA_M if lying else 0.0)
		if off < clearance:
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
	if body.threat_err > FRAG_MAX_ERR_M:
		return  # only cracks overhead, the shooter never seen: no frag at a guess (G-03)
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


## "Reloading!", or "Last mag for the rifle!" (etc.) when this reload uses the last of the
## weapon's ammo this soldier carries: a bounded ammo-status call, templated by weapon class
## (not caliber, which Piper would need far too many pre-rendered lines for) so it stays a
## handful of lines, not one per gun.
func _callout_reload(weapon: ItemData) -> void:
	var mag := _mag_size(weapon)
	if mag > 0 and body.inventory.spare_rounds(Soldier._ammo_of(weapon)) <= mag:
		_callout(StringName("reloading_last_%s" % _weapon_class(weapon)))
	else:
		_callout(&"reloading")


## "rifle", "mg" (belt-fed or LMG) or "pistol": `weapon`'s class for ammo-status callouts.
static func _weapon_class(weapon: ItemData) -> String:
	if weapon.tags.has("lmg"):
		return "mg"
	return "pistol" if weapon.tags.has("pistol") else "rifle"


## Bounding in contact: "Moving!", and the battle buddy answers "Covering!".
func _call_bound() -> void:
	_callout(&"moving")
	var mate := buddy
	var mate_ai := SquadAI.of(mate) if is_instance_valid(mate) and mate.vitals.is_up() else null
	if mate_ai and not mate_ai.bounding:
		mate_ai._callout(&"covering")


# --- Steering -------------------------------------------------------------

func _go(point: Vector3, run := false) -> void:
	if post:
		point = post.keep_in(point)  # a garrison stays inside its walls (GarrisonPost) until it breaks
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
	if _keeps_apart():
		dir = _apart(dir)
	var local := body.global_basis.inverse() * dir
	body.move_input = Vector2(local.x, local.z)
	var foe := _foe()
	body.want_sprint = _run and not body.want_crouch and foe == null and _may_sprint()
	if foe == null and dir != Vector3.ZERO and body.carrying == null:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-TURN_RATE * get_physics_process_delta_time()))
		body.head.rotation.x = lerpf(body.head.rotation.x, 0.0, 0.1)
	elif dir != Vector3.ZERO and body.carrying != null:
		# Carrying or dragging (Captain, 2026-10-17: "they tend to face the way they should be
		# dragging their teammate and freeze up"): the body turns to the way it goes, slower than
		# empty-handed, so the casualty trails behind it (Soldier.carry_transform) instead of the
		# carrier walking sideways or backwards into them.
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-TURN_RATE * CARRY_TURN_MULT * get_physics_process_delta_time()))
	elif foe == null and dir == Vector3.ZERO and _watch_point() != null and intent != Intent.CASUALTY:
		_aim_at(_watch_point())  # suppressing, or watching a sector
	elif foe == null and dir == Vector3.ZERO and in_contact() and not (intent == Intent.CASUALTY and care == Care.TREAT):
		_aim_at(body.threat_pos + Vector3.UP * 1.2)
	elif foe == null and dir == Vector3.ZERO and suspecting() and intent != Intent.CASUALTY:
		_aim_at(_suspect_pos + Vector3.UP * 1.0)  # something there: look (Spotting)


## Whether this unit keeps its distance from squadmates now (SEPARATION_M): following, or
## fighting while following, on its feet and carrying nobody.
func _keeps_apart() -> bool:
	if squad == null or not _friendly() or body.carrying != null or body.stunned_s > 0.0:
		return false
	return intent == Intent.FOLLOW or (intent == Intent.FIGHT and order == Squad.Order.FOLLOW)


## `dir` (flat, unit or zero) turned off squadmates within SEPARATION_M (Captain, 2026-10-14:
## they bunched up). Standing still, it steps off one within STACK_M, unless it's in cover.
func _apart(dir: Vector3) -> Vector3:
	var push := Vector3.ZERO
	var stacked := false
	var at := body.global_position
	for other: Soldier in squad.neighbours():
		if other == body or not is_instance_valid(other) or not other.vitals.is_up():
			continue
		var away := Vector3(at.x - other.global_position.x, 0.0, at.z - other.global_position.z)
		var d := away.length()
		if d >= SEPARATION_M:
			continue
		if d < 0.05:
			var a := float(body.get_instance_id() % 628) / 100.0  # right on top: each his own way out
			away = Vector3(cos(a), 0.0, sin(a))
			d = 0.05
		push += away / d * (1.0 - d / SEPARATION_M)
		stacked = stacked or d < STACK_M
	if push == Vector3.ZERO:
		return dir
	if dir != Vector3.ZERO:
		if squad.resolved(body.fire_team if body.fire_team >= 0 else 0).spacing == "tight":
			return dir  # a town, a doorway: two side by side pushed apart walk into the jambs (casualty soak, Echo and Foxtrot)
		var turned := dir + push
		return turned.normalized() if turned.length() > 0.2 else dir
	if stacked and not _at_cover():
		return push.normalized()
	return dir


## Where the escort leading an HVT walks: ESCORT_LEAD_M off the lead, on this unit's side.
func _escort_lead_spot() -> Vector3:
	if squad == null or not is_instance_valid(squad.leader):
		return body.global_position
	var lead := squad.leader.global_position
	var off := Vector3(body.global_position.x - lead.x, 0.0, body.global_position.z - lead.z)
	if off.length() < 0.5:
		off = -squad.heading if squad.heading != Vector3.ZERO else Vector3.BACK
	return NavigationServer3D.map_get_closest_point(body.get_world_3d().navigation_map, lead + off.normalized() * ESCORT_LEAD_M)


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


## Whether the casualty lies at `spot` (a lay spot): where its body lies, within LAID_M. The
## one test for "laid down there", so the bearer who stays with them (_care_carry) and the
## carry decision (_should_carry) never disagree about it.
func _lies_at(spot: Vector3) -> bool:
	return _flat_between(casualty.body_point(), spot) <= LAID_M


## Flat distance to `point` (the baked navmesh sits a little above the ground, so 3D distances
## never quite close), or the 3D distance when it's on another floor (FLOOR_DY_M).
## HOLD, out of contact: digs in at the hold point once he's been there DIG_IN_AFTER_S (see
## DIG_IN_AFTER_S). Friendly AI in a zone only (the enemy's sites come dug: Digging.server_prepare).
func _dig_in() -> void:
	if not _friendly() or not body.is_ai() or _flat_distance(_hold_point) > ARRIVE + 0.3 or BaseHub.in_base():  # (the muster line holds too)
		_held_since = -1.0
		return
	var now := Soldier._now()
	if _held_since < 0.0:
		_held_since = now
		return
	if now - _held_since < DIG_IN_AFTER_S:
		return
	var level := CompoundLevel.current(body)
	var terrain: Variant = level.get(&"terrain") if level else null
	if not terrain is ZoneTerrain:
		return
	var dig := Digging.of(body)
	if dig == null or dig.digging(body):
		return
	var t := terrain as ZoneTerrain
	# His cover goes in front of the spot he holds, facing the threat if there is one, else the way
	# his first dig there faced (he looks about between digs).
	var way := body.threat_pos - _hold_point if body.threat_pos != Vector3.ZERO else _dig_way
	way.y = 0.0
	if way.length() < 0.1:
		way = Digging.facing(body)
	way = way.normalized()
	_face(_hold_point + way * 5.0)
	if Digging.cover_at(t, _hold_point, way) >= AI_COVER_TO_M - 0.1 or Digging.problem(body) != "":
		return
	if dig.server_start(body, Digging.COVER, _hold_point, way) == "":
		_dig_way = way
		_callout(&"dig_in", "Digging in!")


func _stop_digging() -> void:
	var dig := Digging.of(body)
	if dig and dig.digging(body):
		dig.server_stop(body)


func _flat_distance(point: Vector3) -> float:
	var flat := Vector2(body.global_position.x - point.x, body.global_position.z - point.z).length()
	return flat if absf(body.global_position.y - point.y) < FLOOR_DY_M else body.global_position.distance_to(point)



static func _mag_size(weapon: ItemData) -> int:
	if weapon == null:
		return 0
	var ammo := Soldier._ammo_of(weapon)
	return ItemDB.get_item(ammo).magazine_rounds() if ItemDB.has_item(ammo) else 0


func _name_of(s: Soldier) -> String:
	if s == null or not is_instance_valid(s):
		return "them"
	return "the lead" if squad and s == squad.leader else s.display_name()
