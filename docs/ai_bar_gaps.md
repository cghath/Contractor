# AI bar: the gaps to close (2026-10-14)

The Captain's bar for Contractor's AI (2026-10-12): **beat Arma 3 AI on Veteran running LAMBS
Danger, VCOM and Lifeline Revive / ACE PIR.** This is the list of what still stands between us and
that bar, worst first, and a short list of where we are already ahead.

It comes from four research notes (vanilla Arma 3, LAMBS Danger 2.6.2, VCOM 3.3 to 3.4.1, and the
medical AI of Lifeline, PIR, ACE3 and KAT), each read against dev `fc98665` (build B0734), and a
critic's pass that checked the shakiest claims against the code and corrected or sharpened
several (G-27 to G-30 and the corrections under "Already ahead" come from it). Every Contractor reference below was read again at `fc98665`; line numbers are from that
commit and will drift, so the function names are the reliable part.

We learn from these mods and are inspired by how they behave. We take no code from any of them
(Lifeline's licence is non-commercial, for one), only the behaviour, and we write it our own way.

## How to read it

- **Priority.** **P0**: a bug, or a hole the player meets in most fights; do first. **P1**: a
  behaviour the bar's AI has and players notice; next. **P2**: a real gap, smaller or situational.
  **P3**: needs a system or assets we haven't built, or can wait.
- **Size.** **S**: one file or two and a regression check, about a day of agent work. **M**: several
  files, a new test scenario, a few days. **L**: a new system.
- **Who has it** names where we learn it from. "Arma" is vanilla Arma 3 at Veteran.
- **Sources.** The Bohemia wiki and feedback tracker block automated reading, so claims from them
  came through search-engine excerpts; the dev.arma3.com patch reports, the BI forums, the UNITAF
  manual and the mods' GitHub source were read directly. VCOM's numbers came through a summary of
  its source. Treat outside numbers as close, not exact.
- Gaps marked **(untested)** were found by reading code, not seen in a run.

## The list

| # | Gap | Pri | Size |
|---|---|---|---|
| G-27 | ~~Hostiles can't pick a target past 200 m~~ (done 2026-10-19: reach by weapon and optic) | P0 | S |
| G-01 | ~~A squadmate sitting in a vehicle blocks casualty care for everyone~~ (done 2026-10-19) | P0 | S |
| G-02 | ~~Every garrison and patrol in a zone is one hostile squad~~ (done 2026-10-19: a squad per site) | P0 | M |
| G-03 | ~~Incoming fire tells the AI exactly where the shooter is~~ (done 2026-10-19) | P0 | S |
| G-04 | ~~The base of fire may be shooting into its own cover~~ (done: _fire_line_state stands him over his cover or moves him to a fire spot) | P0 | S |
| G-28 | ~~A heard shot tells the AI who fired and which side he is on~~ (done 2026-10-19) | P1 | S |
| G-29 | ~~Walls don't muffle shots or footsteps~~ (done 2026-10-19) | P1 | M |
| G-05 | ~~The AI never chooses to go prone~~ (done 2026-10-19: prone in a fight behind folds or far out, flat when pinned in the open) | P1 | M |
| G-06 | ~~Assault and the flank's maneuver element run, they don't bound~~ (done 2026-10-19: buddy-pair bounds in contact, one rush for the last 12 m) | P1 | M |
| G-07 | ~~No instant reaction to a near miss or a blast~~ (done 2026-10-20: near misses and blasts: duck, dash, drop, smoke) | P1 | M |
| G-08 | ~~A building clearance is dropped when contact goes quiet~~ (done 2026-10-19) | P1 | S |
| G-09 | ~~The same bursts at every range~~ (done 2026-10-19) | P1 | S |
| G-10 | ~~The AI shoots the nearest enemy it sees, not the most dangerous~~ (done 2026-10-19: guns, who's on me, keep, low, spread) | P1 | M |
| G-11 | ~~One small suppression radius for every round~~ (done 2026-10-19) | P1 | S |
| G-12 | ~~No cap on how many leave the fight for casualties~~ (done 2026-10-19: 1 plus the medics, in contact) | P1 | S |
| G-13 | ~~A carer stays with a casualty who is already stable~~ (done 2026-10-20: leaves for a worse one nobody can answer, comes back) | P1 | M |
| G-14 | ~~Smoke and bangs only on break contact, casualty reach or an order~~ (done 2026-10-21: smoke over open ground crossed under fire and over a casualty dragged off; bangs into a hot building with no breacher and up each stair push) | P1 | M |
| G-15 | ~~Doctrine numbers still don't act~~ (done 2026-10-20: every number scales the AI's own, Doctrine.factor) | P1 | M |
| G-16 | ~~The AI never judges which casualty is worst~~ (done 2026-10-19: its own read when no card) | P2 | S |
| G-30 | ~~Only an AI medic can give CPR or shock a heart~~ (dropped, Captain 2026-10-19) | - | - |
| G-17 | Positions are picked without terrain, height or a second threat (done 2026-10-20: base of fire takes high ground, flanks like height, folds count as cover, gun teams pick defilade against every known enemy, cover against a second group) | P2 | M |
| G-18 | ~~No first-contact drill (freeze, face, get down)~~ (done 2026-10-20) | P2 | S |
| G-19 | ~~Nothing avoids ground that is being shot up~~ (done 2026-10-20: cover choice, so bounds and moves too) | P2 | M |
| G-20 | ~~Infantry don't react to armour~~ (done 2026-10-20, first pass: crewed IFVs and tanks in sight are a threat to take cover from, smoke when close with no launcher near) | P2 | M |
| G-21 | ~~Every flank is the same close hook~~ (done 2026-10-20: the other side next time, sometimes wide) | P2 | S |
| G-22 | ~~A lost enemy is searched for where he was, not where he was going~~ (done 2026-10-20) | P2 | S |
| G-23 | ~~Few visible reactions to being hit~~ (done 2026-10-20: flinch and limp were in; a forearm hit can knock the weapon out (picked back up), a badly hurt man crawls to cover) | P2 | M |
| G-24 | ~~No night, light, NVG, fog or weather in spotting~~ (done in wave 7: darkness, weather sight and fog, NVGs, flash and lights at night; enemy flares done 2026-10-21: hand flares and mortar illumination light the ground, spotting reads it, NVGs bloom) | P2 | M |
| G-25 | No enemy fire support: mortars, static guns; static weapon teams that move where they're needed (done 2026-10-20 for both sides and players, first pass: see docs/static_weapons.md) | P1 | L |
| G-26 | ~~Patrols don't ambush; no mines~~ (done 2026-10-20: half the enemy's patrols lie in wait when they suspect someone; roadside IEDs are the mines; formation variety done 2026-10-21: patrols walk in formation by ground and threat, spacing by doctrine) | P3 | M |

G-27 to G-30 were added from the critic's pass (the gaps are numbered in the order they were
found, not by priority).

Suggested batches: the five P0s first (four are S; G-27 is a constant and a check). Then G-05, G-06 and G-07 together, since all
three are how a unit moves and gets down under fire. G-12, G-13 and G-16 together as one casualty
pass. G-09, G-11 and G-15 together, as the numbers behind firing and suppression.
G-28 and G-29 together, as one hearing pass.

**Work order (2026-10-19, with the Captain's static weapon teams queued by what they build on):**
1. The P0s: G-01, G-03, G-27, G-02 (written; G-04 done).
2. G-09, G-11 and G-15: bursts by range, suppression by round, doctrine numbers. A gun team's
   whole job is suppression, so the numbers behind it come first.
3. G-17: picking positions with terrain, height and a second threat. "A gun on a hill" is this.
4. **G-25, static weapon teams** (Captain: "queue it appropriately"). In parts:
   a. the static weapon itself: a tripod HMG (M2 / DShK) that packs into loads two or three men
      carry, sets up, and is crewed like a vehicle gun;
   b. the AI team: moves the gun to high ground over the fight (G-17) and suppresses (G-09/G-11);
      hostile, allied (the wave 6 weapons team) and rebel;
   c. mortar teams: move until the target is in range, range in on Alert's last known position,
      then fire for effect; stopped by their comms;
   d. players: order a friendly team there (command menu, map orders, high command) and carry and
      set up a gun themselves.
5. G-05, G-06, G-07: getting down and bounding under fire.
6. G-28 and G-29: the hearing pass.
7. G-08, G-10, G-14: clearing, target choice, smoke and bangs.
8. G-12, G-13, G-16: the casualty pass (G-30 dropped by the Captain).
9. The P2s, then G-26.

Working near other lanes: `squad_ai.gd`'s body carrying belongs to the coop-respawn worktree
right now, so the casualty gaps (G-01, G-12, G-13, G-16) wait for it or keep clear of that code.
`ai/movement-quality` (8edafab, unmerged WIP) is only a motion probe so far and doesn't touch any
gap here.

---

## P0

### G-27: hostiles can't pick a target past 200 m

- **The behaviour.** An enemy who can see you at 300-400 m shoots at you, with the accuracy that
  range deserves.
- **Who has it.** Arma's AI at Veteran engages out to its weapon's and its spotting's reach, well
  past 200 m in open country (the exact Veteran skill numbers are unverified; dump them in-game with
  `skillFinal` before tuning against them).
- **Contractor now.** Target choice stops at `SquadAI.SIGHT_RANGE` (200 m, `squad_ai.gd:140`) for
  hostiles and `SQUAD_SIGHT_RANGE` (300 m, `:385`) for the squad (`_find_target`, `:2745`).
  `Doctrine.engage_m` clamps to that sight range too (`doctrine.gd:62`). Hostiles still hear shots
  out to 200 m and go to search (`server_heard_shot`, `:643-662`), so they react past 200 m; they
  just never get a target there. The squad out-ranges every hostile by 100 m.
- **Proposed work.** It's a constant, not a system: raise the hostile sight range (by weapon and
  optic, so a rifle with irons doesn't snipe), let `Doctrine.engage_m` set each faction's real
  range under it (G-15), and make sure long-range aim error and G-09's slower fire keep it fair.
  A check: a hostile on a rise with a scoped rifle engages a squad crossing open ground at 300 m.
- **Size** S. **Priority** P0.

### G-01: a squadmate sitting in a vehicle blocks casualty care for everyone (untested)

- **The behaviour.** Whoever is picked to answer a casualty must be able to reach them. A unit in
  a vehicle, on a mounted gun or driving isn't picked.
- **Who has it.** Lifeline leaves out anyone driving, flying, on a mounted weapon, in armour, with a
  launcher out or hunting a tank, and anyone too far off.
- **Contractor now.** Getting into a vehicle switches the unit's brain off
  (`vehicle.gd:627-629`). `SquadAI._free_for` (`squad_ai.gd:1317`), `responder_for` (`:1258`) and
  `medic_for` (`:1293`) never check `body.vehicle`. Everyone else steps aside for the chosen
  responder (`_find_casualty`, `:1370-1373`), so nobody comes. Not just medics: a seated battle
  buddy, a seated second medic, or a seated unit who happens to be nearest all win
  `responder_for` and block the casualty.
- **Proposed work.** `_free_for` is false while `body.vehicle != null`. A casualty test: seat the
  fire team's medic in a vehicle, down a squadmate, and check the battle buddy answers.
- **Size** S. **Priority** P0.

### G-02: every garrison and patrol in a zone is one hostile squad

- **The behaviour.** A group plans with its own men and what it knows. Other groups hear about it
  by radio, with range and delay.
- **Who has it.** LAMBS gives a tactic only to units near the leader (`findReadyUnits`: 200 m by
  default, 150 m for a garrison, 250 m for an assault); other groups learn through range-limited
  `doShareInformation`. Arma keeps one knowledge base per group.
- **Contractor now.** One `Squad` per faction (`compound_level.gd:194-199`; `:828`
  `brain.squad = squad_for(faction)`), and every garrison post spawns into it
  (`zone_level.gd:428-430`). The `guard` flag only affects `_patrol` (`squad_ai.gd:1178`), and a
  tactic's task (score 0.75) beats patrolling (0.3). So `SquadTactics._free_units`
  (`tactics.gd:406`) can send a whole zone's hostiles into one flank: run S0706 (on 9a1046c, not
  fc98665) logged one compound's garrison and a checkpoint's flanking together. `Squad.note_enemy`
  (`squad.gd:118`) also gives the whole zone what any one man sees, at once, which steps around
  `Alert`'s radio-delay model (`alert.gd`). Hunter teams and reinforcement waves already get their
  own squads (`enemy_response.gd:598`, `reinforcements.gd:189`); this is garrisons and patrols.
- **Proposed work.** One hostile `Squad` per site garrison and per patrol, each knowing only what
  its own men see and hear, plus what `Alert` reports reach it (with its delays). As a first step
  if that's too big: `_free_units` takes only units in contact or within about 200 m of the
  squad's contact cluster.
- **Size** M. **Priority** P0.

### G-03: incoming fire tells the AI exactly where the shooter is

- **The behaviour.** A round going past tells you roughly which way it came from, not the spot.
- **Who has it.** Arma: a hit raises knowledge of the shooter, but its `targetKnowledge` carries a
  position error, and a heard shooter is placed with a large error. Contractor already does
  hearing this way.
- **Contractor now.** `Ballistics.report_near_misses` (`ballistics.gd:330-340`) passes the
  shooter's muzzle position, and `Soldier.suppress` (`soldier.gd:225-228`) sets `threat_pos` to it
  exactly. Cover (`find_cover`), the push forward, and frags (`_maybe_frag`, `squad_ai.gd:3234`)
  all aim at `threat_pos`, so a frag can land on the exact muzzle of a man nobody has seen. A
  heard shot, by contrast, gets 6 m of error per 100 m (`HEARD_ERROR_PER_100M`, `:376`, `:656`).
  It gives the position, not the shooter as a target: he still has to be spotted.
- **Proposed work.** On a near miss, `threat_pos` gets an error: good direction, poor range (the
  crack-thump problem), growing with distance, shrinking while the shooter is in the view cone or
  keeps firing. Frags only when the error is small enough or the shooter is seen. Keep the
  explosion and flashbang `suppress` calls as they are (a blast's centre is plain to see).
- **Size** S. **Priority** P0.

### G-04: the base of fire may be shooting into its own cover (untested)

- **The behaviour.** Suppressive fire is only worth it when the rounds reach the target's area.
- **Who has it.** LAMBS `doSuppress` traces the line, pulls the aim point back to the first thing
  it hits, and only fires when that obstacle is within 5 m of the target (`minObstacleProximity`),
  with a reverse check.
- **Contractor now.** `_shoot` (`squad_ai.gd:3090`) fires at `_suppress_point()` or `threat_pos`
  with only the friendly-in-line check; with no seen foe, `_gate_open` checks a 6° aim error and
  nothing else (`:2992-2997`). A unit stands to fire over cover only with a seen foe
  (`:3110-3112`). `_fight` keeps it crouched at cover otherwise; crouched eyes are at 1.0 m
  (`soldier_movement.gd:27`), and cover is chosen because it blocks the line at 0.9 m
  (`_cover_protects`, `:2903`). So the base's rounds very likely go into its own wall.
- **Proposed work.** Check first with a short headless probe (a base of fire behind a low wall:
  where do its rounds land?). Then: before a burst at a point, trace from the eyes; if the first
  hit is near the shooter, stand to fire over the cover; if it is short of the target by more than
  about 5 m, move the aim or hold fire. Same check for the casualty-cover and covering fire paths.
- **Size** S. **Priority** P0.

---

## P1

### G-28: a heard shot tells the AI who fired and which side he is on

- **The behaviour.** A shot heard but not seen is a sound from roughly over there. You can't tell
  by ear whether it was your own side, and you certainly don't know which man fired.
- **Who has it.** Arma's AI can't tell friendly from enemy fire by sound. (VCOM goes the other
  way: every shot gives all enemies within 800 m an instant fix. We learn from Arma here.)
- **Contractor now.** `server_heard_shot` (`squad_ai.gd:643-662`) skips listeners of the shooter's
  own faction, so a hostile never reacts to his own side's shots and always reacts to ours. It then
  calls `hear(shooter, ...)` (`:668`), raising awareness of that exact soldier and putting him in
  the squad picture (`Squad.note_enemy`). Footsteps are heard at the walker's exact position
  (`_find_target`, `:2766-2772`). The heard-position error is a uniform square of +-6 m per
  100 m, so up to about 8.5 m per 100 m diagonally, not 6.
- **Proposed work.** A heard shot makes an anonymous sound contact (a position with its error)
  that a listener investigates whoever fired, unless he knows a friendly is there (his own
  squad's known positions); awareness of a soldier only builds once he is seen. Footsteps get a
  small position error. Make the error round, not square.
- **Size** S. **Priority** P1.

### G-29: walls don't muffle shots or footsteps

- **The behaviour.** Gunfire inside a building, or footsteps on the far side of a wall, carry less
  far.
- **Who has it.** Arma: footsteps depend on speed and are muffled by solid objects.
- **Contractor now.** `HEAR_SHOT_M` 200, `HEAR_SUPPRESSED_M` 40 and `Spotting.footsteps_m`
  (`spotting.gd:221`: 25 m running, 12 m walking, 5 m crouched) are straight distances; nothing
  traces between source and listener (`server_heard_shot`, `_find_target`).
- **Proposed work.** For listeners already in range, one ray to the source; each wall or building
  shell in the way cuts the reach (say by half for shots, to nothing for footsteps through more
  than one wall). Keep it cheap: only candidates in range, cached per shot.
- **Size** M. **Priority** P1.

### G-05: the AI never chooses to go prone

- **The behaviour.** Prone when pinned in the open, when firing from far with nothing to hide
  behind, on overwatch; crawl to cover.
- **Who has it.** Arma's COMBAT mode goes crouched or prone unless moving and sometimes crawls in
  cover; LAMBS's flankers move prone.
- **Contractor now.** Prone only comes from a squad order (`STANCE_ORDERS`, `squad_ai.gd:106`, set
  in `squad.gd:426-427`) or a broken pelvis (`soldier_movement.gd:183-184`). On its own the AI only
  sets `want_crouch` (`_fight`, `:1096`). A pinned squadmate's "crawl" to cover is a crouched walk
  (`:1069`, `:1080`); pinned hostiles crouch where they are. Spotting already rewards prone (time
  to spot ×2.5, `spotting.gd`), so prone is a big lever we don't pull.
- **Proposed work.** Pinned in the open: prone, then a real crawl (`PRONE_SPEED`) to cover within
  `PINNED_COVER_M`. No cover and firing past about 100 m, or on a watch task: prone if the line
  from prone eye height is clear. Keep crouch behind low walls where prone can't see over. Never
  for a downed unit (Captain, 2026-10-11: no crawling while down).
- **Size** M. **Priority** P1.

### G-06: assault and the flank's maneuver element run, they don't bound

- **The behaviour.** Moving under fire in turns: one pair moves while the other covers.
- **Who has it.** Arma's COMBAT mode bounds. VCOM's `ForceMove` sends half the group to cover
  within 30 m while the other half suppresses, every 40 s. LAMBS's flankers alternate halves
  suppressing every 11-19 s while moving.
- **Contractor now.** Assault is `_go(point, true)` for everyone (`_do_tactic`,
  `squad_ai.gd:2437-2444`); the maneuver element runs its route leg by leg the same way
  (`_tactic_maneuver`, `:2543-2556`). `_bound_toward` (`:2613`) only serves break contact and the
  ordered bound. The comments say otherwise (`tactics.gd:24`, `:504`: "bound onto the position").
- **Proposed work.** Assault and maneuver legs go through `_bound_toward` by buddy pairs, the still
  pair firing at the cluster. Correct the comments.
- **Size** M. **Priority** P1.

### G-07: no instant reaction to a near miss or a blast

- **The behaviour.** A round cracks past or a grenade lands: in the next moment the unit dodges,
  drops or dives for the nearest cover, before it thinks about the plan.
- **Who has it.** LAMBS's immediate layer (`brainReact`: Fire, Hit, Explosion, BulletClose) takes
  cover when suppression is above 0.5 or the unit is stopped, otherwise dodges (`doDodge`,
  `doCover`). Arma 1.48 added smoke when suppressed.
- **Contractor now.** Intents are chosen every 0.5 s (`THINK_S`) with hysteresis
  (`_choose_intent`, `squad_ai.gd:884`); suppression feeds aim error and the pinned state. Only a
  pinned squadmate (0.85) moves to cover within 6 m; hostiles stay where they are.
- **Proposed work.** A short reaction on `suppress()` and on a hit, ahead of the intent: a
  sidestep or drop (G-05) or a dash to cover within about 3 m, then back to the intent. Not while
  treating, carrying or on a ground order to hold exactly. Throwing smoke when pinned in the open
  (the code for screening smoke already exists, `_screen_toward_threat`, `:2646`).
- **Size** M. **Priority** P1.

### G-08: a building clearance is dropped when contact goes quiet

- **The behaviour.** Once you start clearing a building, you finish it unless something bigger
  happens.
- **Who has it.** LAMBS keeps the building's positions in group memory until a unit has seen each
  one within 5 m, and its state machine keeps re-checking while that memory isn't empty.
- **Contractor now.** CLEAR only scores while there is contact or a sighting under 6 s old
  (`SquadTactics.assess`, `tactics.gd:330`); when it stops scoring, `switches()` drops it at once
  (`:206-208`). Contact memory is 8 s for hostiles and 20 s for the squad (`squad_ai.gd:109`,
  `:386`), while a two-floor clearance needs 8 s to stack plus 8 s a floor. A clearance ordered
  from the command menu does carry on.
- **Proposed work.** CLEAR stays while its clear op has rooms nobody has reached, unless the squad
  takes a casualty, breaks contact or gets an order. A test: clear a two-floor building with the
  enemy silent after the first room.
- **Size** S. **Priority** P1.

### G-09: the same bursts at every range

- **The behaviour.** Bursts up close, short bursts in the middle, single aimed shots far out;
  slower fire the further the target.
- **Who has it.** Arma picks a fire mode by range from each mode's hit chances and spaces shots by
  distance (`aiRateOfFire`, `aiRateOfFireDistance`).
- **Contractor now.** `_shoot` (`squad_ai.gd:3090`) fires bursts of 3 to 5 from any automatic
  weapon and 2 to 3 from a semi-auto, with a pause of about a second between bursts, whatever the
  range. Doctrine's
  `burst` and `burst_pause` are pending (G-15).
- **Proposed work.** Range bands per weapon class: rifles go to short bursts past about 30 m and
  single aimed shots past about 150 m, with the pause growing with range; machine guns keep
  bursts. Doctrine scales them once G-15 lands (insurgents longer bursts, PMC controlled).
- **Size** S. **Priority** P1.

### G-10: the AI shoots the nearest enemy it sees, not the most dangerous

- **The behaviour.** Shoot what threatens you most: the machine gunner, the man with a launcher,
  whoever is shooting at you, someone in the open before someone behind cover. Spread a squad's
  fire rather than all on one man.
- **Who has it.** Arma weighs targets by threat and cost from the unit config, and leaders assign
  targets.
- **Contractor now.** `_find_target` (`squad_ai.gd:2734`) takes the nearest fully spotted enemy
  (`:2774-2778`). A target the squad leader orders (`focus`, `:2737-2743`) overrides it.
- **Proposed work.** Score seen enemies by range, weapon (MG, launcher), whether they are firing
  at this unit or its buddy (`threat_pos`), exposure, and how many squadmates already have them;
  keep the current target unless another clearly beats it.
- **Size** M. **Priority** P1.

### G-11: one small suppression radius for every round

- **The behaviour.** Heavier rounds suppress further; rounds hitting nearby suppress too.
- **Who has it.** Arma sets two radii per round in its ammo config: rounds passing by
  (`suppressionRadiusHit`) and impacts close by (`suppressionRadiusBulletClose`). (Arma's rifle
  rounds of different power all suppress the same, so this is a place to beat it.)
- **Contractor now.** `SUPPRESS_RADIUS := 2.5` for every round (`ballistics.gd:33`), measured to
  the line from muzzle to impact (`report_near_misses`, `:330-340`). Blasts and flashbangs
  suppress on their own (`throwables.gd:123`, `warheads.gd:300`, `:520`).
- **Proposed work.** Radius and amount by round class (pistol small, intermediate as now, full
  power and .50 wider), and an impact splash radius. Machine-gun fire stacks naturally.
- **Size** S. **Priority** P1.

### G-12: no cap on how many leave the fight for casualties

- **The behaviour.** In a firefight, only as many go to the wounded as the squad can spare.
- **Who has it.** Lifeline's `Lifeline_Medic_Limit`: 1, 2 or 3 per group plus anyone not under
  fire, "to keep combat effectiveness up"; it picks the least suppressed.
- **Contractor now.** Every casualty gets its own responder (`responder_for`,
  `squad_ai.gd:1258`), and CASUALTY (0.9) beats FIGHT (0.7) in `_choose_intent`. Three casualties
  take three shooters out of the fight. The tactics option for casualties has the others suppress.
- **Proposed work.** In contact, a squad cap on carers out in the open (proposed: the medics plus
  one, or a share of the squad up), with units at cover and unsuppressed exempt. The rest wait and
  cover. Out of contact, no cap.
- **Size** S. **Priority** P1.

### G-13: a carer stays with a casualty who is already stable (untested)

- **The behaviour.** Once a casualty is stable, the medic can go to the next one, and come back.
- **Who has it.** Lifeline hands a casualty to a closer free unit when the assigned medic is over
  100 m off, and resets a medic idle for 7 s.
- **Contractor now.** `needs_help` is true for as long as a casualty is down (`squad_ai.gd:1211`),
  `Care.GUARD` keeps the carer beside them (`:1488`), and `_free_for` needs `care == NONE`
  (`:1317`), so a medic watching a stable unconscious casualty can't answer a new arterial bleed.
  `_choose_intent` also won't leave a casualty for anything under 0.95 (`:947`).
- **Proposed work.** When a casualty has nothing urgent left, the carer may hand them over (anyone
  free can watch) and a medic may leave for a worse casualty (G-16), coming back after. Also hand
  over to a closer free unit when the responder is far.
- **Size** M. **Priority** P1.

### G-14: smoke and bangs only on break contact, casualty reach or an order

- **The behaviour.** Smoke to cover a crossing or a flank; a bang or a frag into a room before
  going in; smoke when pinned.
- **Who has it.** LAMBS throws smoke toward the flank's overwatch and in its group plans; VCOM's
  moving units have a 10% smoke chance; Arma 1.48 smokes when suppressed. Our design doc calls
  for grenades, flashbangs and smoke in the AI's tactics (`contractor_design_doc.md:273`).
- **Contractor now.** Frags only in the FIGHT intent at 8-25 m after 4 s without sight
  (`_maybe_frag`, `squad_ai.gd:3234`), so never while clearing. Smoke goes out on break contact
  (`_screen_toward_threat`, `:2646`) and when reaching a casualty in the open (`SMOKE_RANGE_M`,
  `:1563`). Flashbangs only when ordered (`order_throw`, `:788`).
- **Proposed work.** The maneuver element smokes open ground on its route (as break contact
  already does); the entry team bangs (or frags, by doctrine) a room before entry, never with
  civilians or an HVT inside as far as the squad knows. Pinned in the open: smoke (G-07).
- **Size** M. **Priority** P1.
- **Done 2026-10-21** (claude/ai-followups). Smoke: `SquadAI._smoke_crossing` puts smoke between
  the way and the threat when a move in contact crosses CROSS_OPEN_M (15 m) or more of open ground
  the threat sees (its middle and two thirds in view, nothing in the way), once a squad near there
  (`_screened`): a bound (`_bound_toward`, once for the whole bound), a fall back, a move order, and
  a casualty dragged or carried off in the open (from 3 m). Bangs: `Squad.bang_wanted` (an enemy
  known inside, or a fight with one within 35 m of it; never a noncombatant inside) gives a stack
  with no breacher an entry bang (`Squad.entry_bang`), and before each stair push the carrier goes
  to the stair's foot and bangs up past the top (`_plan_stair_bang`, `_stair_bang`); the push goes
  once it's gone off. Our side bangs with a flashbang first, the enemy a frag first
  (`Squad.bang_of`). squad_test checks the crossing smoke and the stair bang.

### G-15: doctrine numbers still don't act (audit A3-07)

- **The behaviour.** Different enemies fight differently: range, reaction, aim, bursts, grenades,
  morale, flanking.
- **Who has it.** Arma's per-unit skills (aiming accuracy, shake, speed, spot distance and time,
  courage, reload speed, commanding); LAMBS and VCOM settings per mission. Our doctrines go
  further by giving each faction a way of fighting.
- **Contractor now.** `Doctrine.PENDING` (`doctrine.gd`): engage range, reaction, aim, burst and
  pause, cover fire, frag timing, morale thresholds, advance timing and flank are read by nothing;
  only the option biases act (`SquadTactics.DOCTRINES`, `tactics.gd:141`). The audit left this to
  the Captain's tactics work.
- **Proposed work.** Wire each weight into the decision its note names, one at a time, each with a
  check, and take it off PENDING. G-09 is a natural first.
- **Size** M. **Priority** P1. Captain's side.

---

## P2

### G-16: the AI never judges which casualty is worst

- **The behaviour.** With several down, go to the worst first (and in co-op, perhaps players).
- **Who has it.** Lifeline treats players first, then AI group by group. Nobody in the bar sorts
  by how badly hurt; this would put us ahead.
- **Contractor now.** `_find_casualty` (`squad_ai.gd:1347`) goes by triage tier, then distance
  (`triage_tier`, `:1387`). But only a player sets triage cards (`medical_menu.gd:150` to
  `vitals.gd:844`); with no cards, it's the nearest casualty, a medic favouring its own fire team.
- **Proposed work.** With no card set, the AI rates a casualty from `care_needed()` (massive
  bleeding, airway or a tension chest: immediate; and so on). Optionally, players first within a
  tier.
- **Size** S. **Priority** P2.

### G-30: only an AI medic can give CPR or shock a heart

- **The behaviour.** When the medic is down or far off, someone else starts CPR on a casualty in
  cardiac arrest.
- **Who has it.** Lifeline lets any squad AI turn medic for a revive, CPR included. ACE3's medical
  AI goes to CPR right after stopping the bleeding.
- **Contractor now.** `_may_use` (`squad_ai.gd:1338`) keeps every `medic_only` item (CPR, the
  defibrillator) for medics among the AI, and the care loop skips them for anyone else (`:2081`,
  "players and medics only"). With the medic down, an arrested casualty gets no CPR from the AI
  and the cardiac-arrest window runs out. (No instant death does hold for both sides:
  `can_go_down`, `vitals.gd:84`, defaults to true and only a test sets it false. The `vitals.gd`
  header saying nothing restarts a heart until wave 3 is stale: CPR and the defib are in,
  `vitals.gd:335`, `:543`.)
- **Proposed work.** Captain's call, since medic-only was a design choice. Suggested: any AI may do
  CPR when no medic can reach the casualty within a set time; the defibrillator stays medic-only.
- **Captain, 2026-10-19: not needed.** CPR and the defib stay medic-only among the AI; players keep
  full medical ("full medical for players is a must").
  Fix the stale header in the same change.
- **Size** S. **Priority** P2.

### G-17: positions are picked without terrain, height or a second threat

- **The behaviour.** Overwatch from a hill, a treeline or a building; flank through dead ground;
  cover that works against more than one enemy.
- **Who has it.** LAMBS scores the flank's overwatch for hills, forest and houses, and won't charge
  uphill at a vaguely known enemy over 300 m off (it suppresses, then hides). VCOM's flank points
  score hills 6, houses 4 and trees 2, and it has high- and low-ground attacks.
- **Contractor now.** `flank_route` (`tactics.gd:613`) ends 15-45 m from the enemy, on the side he
  sees least of and away from other known groups. `find_cover` (`squad_ai.gd:2877`) looks 2-10 m
  out and only against one point, `threat_pos`.
- **Proposed work.** Score flank points and base-of-fire spots for height, foliage
  (`ZoneScatter`) and building ports; a wider search for squad positions; cover tested against
  the squad's known clusters, not one point.
- **Size** M. **Priority** P2.

### G-18: no first-contact drill (freeze, face, get down)

- **The behaviour.** On contact the group stops, turns to the threat and gets down while the leader
  decides.
- **Who has it.** LAMBS's `fnc_contact`: the leader freezes, a unit points and calls it, the group
  faces the enemy and crouches, the leader moves into cover within 35 m, and the leader radios it
  1-5 s later.
- **Contractor now.** The contact callout (`squad_ai.gd:591`), voice and radio sharing (`:682`)
  and the squad's call (`tactics.gd:853`) are in; there's no freeze or face.
- **Proposed work.** For 1-3 s after first contact, every free unit faces the reported bearing and
  gets down before the tactics option takes over.
- **Size** S. **Priority** P2.

### G-19: nothing avoids ground that is being shot up

- **The behaviour.** Don't move through where the rounds are landing.
- **Who has it.** Arma's suppression (1.42) has AI avoid crossing impact zones.
- **Contractor now.** `flank_route` avoids ground the enemy can see, but nothing remembers where
  rounds landed, and `_go` paths ignore it.
- **Proposed work.** The squad keeps recent impact and near-miss points for 10-20 s; routes,
  bounds and cover choice avoid them.
- **Size** M. **Priority** P2.

### G-20: infantry don't react to armour

- **The behaviour.** A tank close by: get out of its sight, let the anti-tank gunner work, keep the
  infantry off him.
- **Who has it.** LAMBS hides from a tank within 450 m, and attacks a light vehicle within 120 m
  when the group has anti-tank.
- **Contractor now.** `LauncherAI` (`launcher_ai.gd`) fires launchers at vehicles within 300 m;
  the squad picture (`Squad.known`) and the tactics count only soldiers.
- **Proposed work.** Vehicles in the squad picture; armour raises break contact or a "hide" hold,
  the launcher man gets cover and a shot, the rest suppress its infantry and smoke.
- **Size** M. **Priority** P2.

### G-21: every flank is the same close hook

- **The behaviour.** Attacks on the same enemy vary, and some go wide.
- **Who has it.** VCOM picks one of five attack types (straight in, high ground, low ground, two
  flanks), not repeating one used against the same group in the last 120 s, with flank points
  100-200 m off.
- **Contractor now.** One flank, ending 15-45 m from the enemy (`flank_route`); hot-zone hunter
  teams do go wide (`enemy_response.gd:422`). No memory of the side used last time.
- **Proposed work.** Remember the side used per enemy cluster and lean the other way next; a wide
  variant at 150-250 m.
- **Size** S. **Priority** P2.

### G-22: a lost enemy is searched for where he was, not where he was going

- **The behaviour.** A target that drops out of sight is looked for along his last heading.
- **Who has it.** Arma predicts a lost target's position from his last heading and speed.
- **Contractor now.** `Squad.note_enemy` (`squad.gd:118`) keeps a position and a time; the search
  rings round it (`SEARCH_RING_M`, `tactics.gd:136`).
- **Proposed work.** Keep his velocity too; search and investigate at the last position plus a
  few seconds of his movement.
- **Size** S. **Priority** P2.

### G-23: few visible reactions to being hit

- **The behaviour.** A hit shows: a flinch or stumble, a dropped weapon, a limp, a wounded man
  crawling to cover or panicking.
- **Who has it.** PIR: weapon knocked out, helmet knocked off, cramps, pain reactions, crawling
  and panic before going down, with adjustable chances.
- **Contractor now.** The wound model has stagger, winded and concussion timers
  (`wound_model.gd:372`, `:455`) and a broken pelvis forces prone; a downed man never moves on his
  own (Captain, 2026-10-11).
- **Proposed work.** Conscious wounded AI: a flinch on a hit, a limp with a leg wound, a chance to
  lose the weapon on an arm hit; a badly wounded man may crawl to cover (only while conscious).
- **Size** M. **Priority** P2.

### G-24: no night, light, NVG, fog or weather in spotting

- **The behaviour.** Darkness, fog and rain make people hard to see; NVGs and flares change it.
- **Who has it.** Arma's spotting counts light, fog and NVGs; LAMBS fires flares at night. Our
  design doc lists light and weather among the senses (`contractor_design_doc.md:273`).
- **Contractor now.** `spotting.gd:16-18` waits for day and night (wave 7). Zones have a fixed fog
  (`zone_level.gd:28`) that the AI doesn't read.
- **Proposed work.** With wave 7: a light factor and an NVG factor in `Spotting.spot_seconds`,
  muzzle flash worth more at night, flares. Fog as a range factor can go in now.
- **Size** M. **Priority** P2 (P1 once wave 7 starts).
- **Enemy flares done 2026-10-21** (claude/ai-followups). `Flares` (scripts/combat/flares.gd): a
  parachute flare bursts high and lights the ground round it, full within its "full_m" and fading
  to "edge_m", fading out in its last 4 s; host authoritative, synced to every peer and a late
  joiner. Spotting's `sight_x` takes the darkness away at the one looked at by `light_at`, so a lit
  field is seen almost as by day, by both sides. A hostile who hears contact or takes fire at
  darkness 0.55 or more has his squad put one up over it (`SquadAI._maybe_flare`, once a squad every
  45 s, not where one already lights it): a hand flare (`hand_flare`; one hostile in 4 on the
  standard kit carries 2), else his side's mortar team's illumination round
  (`MortarTeam.illum_for`, `MortarFire.server_fire_illum`). NVGs bloom in the light and looking at a
  flare (`NvgView.bloom`). The daynight suite checks it. 40 mm star rounds and player hand flares
  are F-179.

---

## P3

### G-25: no enemy fire support: mortars, static guns

- **The behaviour.** Enemies call mortars, ranging first and firing for effect as they get surer;
  they man static guns.
- **Who has it.** VCOM (3.4.x) keeps a "location known" score per enemy group, from 1 round 50-100 m
  off up to 3 rounds per gun 2-30 m off, smoke instead with friendlies close, a cooldown between
  calls; its AI man empty static guns within 800 m. LAMBS has artillery waypoints.
- **Contractor now.** None. Decided in design: better-equipped factions call mortars, helicopters
  or drones at high alert, and destroying their comms or mortar sites removes the threat
  (`mission_brainstorm.md:175`); mortars are a contract threat weight (`contracts_gen.gd:41`).
- **Proposed work.** A mortar team at some sites, fed by `Alert`'s last known position and its
  uncertainty (ranging rounds, then fire for effect), stopped by its comms. Static guns at posts.
- **Captain, 2026-10-19: "we also need static weapon teams that can move dynamically to where
  they're needed."** So not only guns fixed at posts: crew-served weapons (a tripod HMG, a mortar)
  as teams of two or three that pack the gun into loads, carry them, and set up again where the
  fight needs them (a flank, a rooftop, a road the squad is on), the way VCOM's AI takes up static
  guns and LAMBS moves its groups. Raised to P1, after the P0s.
- **And (same night):** "mortars sent to reposition for targets to be in range, setting up a gun on
  a hill to suppress the enemy etc should be options for the AI factions and players." So every
  side gets it: hostile, allied and rebel AI move a mortar until the target is in its range and put
  an HMG on high ground over the fight; players can order a friendly team to do the same (the
  command menu / map orders) or carry and set up a gun themselves.
- **Size** L. **Priority** P1.

### G-26: patrols don't ambush; no mines

- **The behaviour.** An alerted patrol sets an ambush; varied patrol formations; mines on roads.
- **Who has it.** LAMBS waypoints: creep and ambush, rush, camp, retreat without firing, random
  patrol formations. VCOM plants mines at its feet or on a road nearby.
- **Contractor now.** Patrols and posts (`_patrol`); stealth engagement range for a hidden squad
  (`STEALTH_ENGAGE_M`). IEDs are planned (`ChrisPlan_handoff.md:248`).
- **Proposed work.** An ambush posture for a suspicious patrol (down, hold fire until close),
  formation variety; mines with the IED work.
- **Size** M. **Priority** P3.
- **Formation variety done 2026-10-21** (claude/ai-followups). A hostile patrol walks its route in
  formation behind its lead (`Squad.patrol_lead`, `SquadAI._patrol` to `follow_point`). The
  dynamic formation (both sides, `Squad.pick_formation`): a line in contact, a staggered column in a
  town, a file in the woods (`_in_woods`: leaves round the lead), on a road a column or a staggered
  column on the alert or in the dark, on open ground a wedge or a staggered column in the dark;
  woods and the dark close the spacing a step. Spacing is scaled by doctrine (doctrines.json
  "spacing": insurgents 0.7, regulars and PMCs 1.0). squad_test checks the table and the doctrine
  gaps; garrison_test a patrol in formation.

---

## Already ahead

Where Contractor already beats the bar, checked at `fc98665`:

- **Camo that's real.** `Spotting.camo()` compares the uniform's colour with the zone's ground in
  CIE Lab, with a bonus for a pattern. Arma gives every man the same camouflage, and uniforms and
  ghillies don't count.
- **Foliage that hides you.** Every 0.7 m of leaves multiplies the time to spot; 1.2 m hides you
  (`Spotting.foliage_m`). Arma's AI is known to see and keep a lock through grass.
- **Honest hearing, mostly.** Heard shots carry up to 6 m of error per 100 m on each axis and
  never give a full spot (at most 0.8 awareness); footsteps by gait. Players call Arma's hearing
  overpowered. But see G-28 (it knows who fired) and G-29 (no walls).
- **Spotting that takes time.** Awareness builds over seconds (`Spotting.spot_seconds`) from range,
  stance, gait, camo, foliage, the view cone, muzzle flash and optics, so there is always a grace
  period; line of sight goes to the target's stance-following aim point and smoke cuts it
  (`can_see`, `SmokeCloud.blocks`). Arma's AI is known to open fire with no grace period.
- **Believable aim.** A turn-speed cap (no spinning round for a headshot), a first-shot error and
  settle time, and a shot gate measured in metres (P0362). Arma's AI is known for laser accuracy
  and near-instant turns.
- **News travels by radio.** `Alert` (`alert.gd`): a hostile reacts to what he sees; the zone only
  learns when he radios it, slower once the mast is down; check-ins, bodies found, states that cool
  slowly. LAMBS, VCOM and Arma share at once. (G-02 leaked around it until a squad per site,
  2026-10-19; the last leaks, F-359 to F-362, were closed 2026-10-31: tests/awareness_test.gd.)
- **A real contact drill.** A base of fire that always keeps the autorifleman (`elements`), a
  maneuver element on the side the enemy sees least of (`flank_route` scores two points per side,
  the mid point and the end, not the whole route), checked on the navmesh, with "no flank"
  remembered for 30 s or until the enemy moves 25 m (`NO_FLANK_S`, `NO_FLANK_MOVED_M`), chosen by
  a scored, logged evaluator with hysteresis. VCOM's flank
  orders move the whole group, with nobody left as a base of fire.
- **Buildings.** Defence from firing ports facing the threat, and clearing stack by stack, room by
  room, floor by floor, with dead-checks on the way.
- **Grenade discipline.** The lob is traced so it doesn't bounce back, no frag near friendlies or
  civilians, and the squad doesn't pile frags on one spot. Arma's AI seldom throws at all.
- **Fire discipline.** No shot with a friendly in the cone or in front of the muzzle.
- **Morale and surrender.** Morale per unit (losses, wounds, suppression, odds, the leader near),
  falling back when broken; a wounded hostile left alone may give up and be cuffed
  (`people_layer.gd`). Arma's flight is group-level only.
- **Casualty care that's honest.** Real items used, from the casualty's own kit first; no captive
  or invincibility trick and no full heal; only an arterial bleed is treated under fire;
  casualties are dragged to cover and carried to the casualty collection point; smoke before
  reaching one in the open; squadmates fire to cover the medic; a carer short of an item calls a
  medic who has it; the deep wound model underneath. Lifeline's default makes enemies ignore the
  medic and casualty, and its revive ends in a full heal; its AI never drags or carries. KAT has
  no AI of its own.
- **Logistics.** Squadmates share ammunition and scavenge by need.
