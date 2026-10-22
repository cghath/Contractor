# Contractor: features compared with the market

Written 2026-10-19 for the Captain. It lists what Contractor has today and sets each feature next
to the nearest games (and Arma mods) on the market: what they do, and where Contractor stands
against them, honestly.

- **What "today" means.** Read from branch `claude/ai-driving` at `c399914` (the newest code):
  `FEATURES.md`, `CHANGELOG.md`, `docs/` and the doc comments at the top of the main scripts.
  The rebel "Locals:" jobs landed right after (both ways: the board and villagers). Designs
  that aren't built (hero squad leaders, ALiVE-style virtualization, the player-built faction) are
  left out or marked as gaps.
- **Wording.** Contractor learns from these games and is inspired by them. Nothing here says it
  takes from them.
- **Sources for the other games.** Mostly well-known public facts. A few were checked on the web
  for this doc (Ground Branch's friendly AI, Ready or Not's Commander mode, Ghost Recon Wildlands'
  rebel supports, Arma Reforger's Conflict supplies). What couldn't be confirmed is listed under
  "Not verified" at the end.
- **Medical** is covered briefly here, because a full 30-criterion study with sources already
  exists: [medical_market_comparison.md](medical_market_comparison.md).
- **Numbers.** Most of Contractor's numbers are still marked Proposed in the code: built and
  tested, but not yet tuned by playtests.

Format per feature: **Now** (what it is in the game today), **Compared with** (one to three
games and what they do), **Standing** (where Contractor is ahead, and where it is simpler or
missing something).

---

## 1. Combat and ballistics

### 1.1 Voxel armour: plates and helmets that wear out where they're hit
**Now.** Plates and helmets are 1 cm voxel objects, and the model you see is the thing that gets
hit. Each round is traced voxel by voxel. Stopped rounds dent; repeat hits on one spot wear
through. Ceramic cracks in zones around each hit and can shatter, steel throws spall, and
polyethylene deforms. Rounds and armour share one NIJ-named ladder (IIA to IV), and a round loses
energy with range. The damage belongs to the item: a dropped plate keeps its holes, and saves keep
them too.

**Compared with.**
- *Escape from Tarkov*: armour classes 1 to 6, plates with their own hit zones, durability that
  drops per hit, and penetration worked out from ammo against armour class.
- *Gray Zone Warfare*: plate carriers with classed plates, and Tarkov-like ammo against armour.
- *Arma 3 + ACE3*: armour values per hit-point region, with ACE's ballistics for range and drop.

**Standing.** Ahead: no other game here models where on the plate you were hit, crack zones on
ceramic, steel spall, or visible holes that stay on the item. Tarkov's durability is one number
per plate. Simpler: the rating ladder is coarser than Tarkov's per-round penetration and damage
tables, and the economy that sits on top of armour (repair, wear, trade-ins) is thin.

### 1.2 Range, materials and penetration
**Now.** Rounds lose energy with range, so a distant M855 can be stopped by a light plate. Wood and
sheet metal can be shot through (with less energy left for whoever is behind them), thick wood
stacks stop rounds, and concrete stops all small arms. Rounds leave the muzzle and deviate from
there, not from the eye.

**Compared with.**
- *Arma 3 + ACE3 Advanced Ballistics*: wind, air density, spin drift and barrel length.
- *Ground Branch*: penetration through materials, built for close-quarters fighting.
- *Ready or Not*: penetration that depends on the material, a real factor for doors and walls.

**Standing.** On par with Ground Branch and Ready or Not for walls. Behind ACE3 Advanced
Ballistics: there's no wind, spin drift or air density, so long-range shooting is simpler.

### 1.3 Weapons, sights and attachments
**Now.** A NATO set (M4A1, Mk18, HK416, M27, L85A2, C8, SCAR-H, M110, M249, M240B, M17), an OPFOR
set (AKM, AK-74, RPK, PKM, SVD) and bolt-action rifles. Loose rounds are loaded into magazines by
hand, and each calibre fills only its own magazines. Scopes are a real picture-in-picture
(SubViewport). Iron sights work. Suppressors, foregrips, weapon lights, visible lasers and IR
lasers mount on rails and stay with the gun. A light or laser that's switched on gets you spotted
sooner.

**Compared with.**
- *Escape from Tarkov*: very deep part-by-part gunsmithing, with PIP scopes.
- *Ground Branch*: wide attachment choice and fine control over the loadout.
- *Arma 3 / Reforger*: a large weapon list. Reforger's optics also use PIP.

**Standing.** Ahead: magazines filled from loose rounds, and lights and lasers that feed the AI's
spotting. Simpler: the roster is about 20 guns, with four attachment types plus optics and muzzles.
Tarkov and Ground Branch go much deeper. The guns are voxel stand-ins (a rework of the MGs, ARs and
bolt-actions is under way).

### 1.4 Shooting feel: stance, lean, rest, sway
**Now.** Three standing heights and three crouching heights, side stances, roll while prone, lean
by hold or toggle, and rest the weapon on a wall, sill or the ground for half the sway and recoil.
Momentum depends on the load you carry. Pain, blood loss, concussion and fractures add sway.
Left-handed shooters are mirrored in full. Mantling, and climbing onto roofs. The first-person
animation pass takes Star Citizen as its reference (carry, reload, stance moves, weapon kick,
compressing the weapon at walls).

**Compared with.**
- *Arma 3*: the stance adjust system Contractor's steps are in the spirit of, plus weapon resting
  and deploying.
- *Star Citizen*: the on-foot animation and gunplay quality the Captain has set as the target.
- *Ground Branch / Ready or Not*: fine stance and lean control for close quarters.

**Standing.** On par with Arma for how much posture control you get, and ahead on injuries that
change how you handle the weapon. Behind Star Citizen on animation fidelity: Contractor's poses
are code-driven on voxel bodies, without motion capture.

### 1.5 Grenades, breaching charges and anti-armour launchers
**Now.** Frags make 3 to 8 fragment wounds, shielded by walls, bodies and armour, and leave craters
in voxel walls. Flashbangs, and smoke in five colours. Breaching charges stick to the world, to
people or to vehicles. Launchers: AT4, Carl Gustaf (HEAT/HE/HEDP), SMAW (HEDP/thermobaric), NLAW,
Javelin (lock, top or direct attack) and RPG-7. They fly as real projectiles with motors, arming
distance and self-destruct. Shaped-charge jets penetrate by millimetres. Backblast is a cone that
reflects off a wall and fills a small room.

**Compared with.**
- *Arma 3 / Reforger*: wide launcher sets, Titan/Javelin-style lock, and backblast with ACE3.
- *Squad*: launchers with real backblast, and HEAT against vehicle armour by facing.
- *Teardown*: explosives that carve voxel structures.

**Standing.** Ahead: warheads carve the same voxel world the fight happens in, and backblast
reflects. Few games combine Arma-level launcher detail with Teardown-style holes. Simpler: no guided
missiles beyond the Javelin and NLAW, no mines or claymores for the player, and no grenade
launchers on rifles.

### 1.6 Night, weather and NVGs
**Now.** Each zone has its own hour, with a sun and moon, and five weather types (clear, overcast,
fog, rain, storm). Darkness and weather slow the AI's spotting and cap how far it can see; storms
ground the helicopters. NVGs in three generations mount on the helmet, with a battery, a narrower
field of view per tube, and green grain. Lowered NVGs give back part of the dark's penalty to
spotting.

**Compared with.**
- *Arma 3*: dynamic weather and time, NVGs, thermals, IR lasers and illuminators; the AI uses NVGs.
- *Ready or Not*: night maps with NVGs as gear.
- *Ghost Recon Wildlands*: day and night cycle and weather; night vision and thermals.

**Standing.** On par for the basics, and the dark properly feeds AI spotting. Missing (from the
changelog): no NVG model on the helmet yet, the AI doesn't wear or use NVGs, no IR illuminators,
no thermals, no spare batteries, and scope pictures aren't green through NVGs.

---

## 2. Medical

The full study is in [medical_market_comparison.md](medical_market_comparison.md). On its 16
general criteria Contractor scores 16, A3 + ACE3 + KAT 15, A3 + ACE3 14, ACE for Reforger 11.5,
Tarkov 8.5 and Gray Zone 8. The five features below are the headline ones.

### 2.1 Wound model: no hitpoints, wound channels through anatomy
**Now.** 14 body parts, with 29 named vessels, organs and bones traced along each round's wound
channel and through its temporary cavity. Hits land on the body's real 0.5 cm voxel shape, with
separate male and female bodies. Round classes set the wound, fracture and pain.

**Compared with.**
- *Arma 3 + ACE3 + KAT*: the deepest milsim medical stack, with wounds per body part by type.
- *Escape from Tarkov*: 7 body parts with HP, light and heavy bleeds, and fractures.
- *Arma Reforger + ACE for Reforger*: hit zones, circulation and breathing.

**Standing.** Ahead: no other game here traces the channel through named vessels and organs or
uses the body's real shape. Simpler: the body doesn't compensate for blood loss, and bleeds never
clot on their own (both noted in the study).

### 2.2 Bleeding, fluids, airway, breathing and heart
**Now.** 6 L of blood, with bleeding scaled by heart output. Arterial, venous, junctional and
internal bleeds each need their own fix. IV in six gauges, and IO, with saline and blood bags.
Shock makes IVs slower or makes them miss, and veins collapse. Per-lung pneumo- and hemothorax,
tension pneumothorax, hidden SpO2 and heart rate read as signs, then CPR, the defibrillator and the
drugs. No revive.

**Compared with.**
- *A3 + ACE3 + KAT*: airway, pneumothorax, IV/IO, pulse oximeter and AED.
- *Arma Reforger + ACE*: circulation and breathing modules.
- *DayZ*: blood volume, transfusions, and saline.

**Standing.** Ahead of KAT on IV mechanics (gauges, shock, vein collapse) and on the bleed type
deciding the fix. On par with KAT on airway and chest injuries.

### 2.3 Fractures, blasts, burns, falls, hearing
**Now.** Open and closed breaks, the pelvis and binder, collarbones, cracked ribs behind plates,
blast lung, overpressure deafness, burns, hypothermia, fall injuries, and brain-fragment wounds
that leave you down but alive.

**Compared with.**
- *Escape from Tarkov*: fractures and splints, and blunt damage through armour.
- *Arena Breakout: Infinite*: fractures and blunt damage.
- *A3 + ACE3 + KAT*: fractures, and some blast effects.

**Standing.** Ahead on breadth. No other game in the study has blast lung or brain fragments.

### 2.4 AI medics and casualty care
**Now.** Who answers is set by order: the fire-team medic, then the battle buddy, then the other
medic. Under fire the medic smokes, drags the casualty to cover and puts on a tourniquet, then
works through the care order in cover. Triage cards are respected. AI treat themselves. Moving a
casualty interrupts treatment, and nobody lifts a casualty someone else is treating. As of today,
players can call for a medic, pick one, or have one come on his own.

**Compared with.**
- *Arma 3 + Lifeline Revive AI / PIR*: AI medics that revive, with a full heal at the end.
- *Arma Reforger*: AI medics that patch up.
- *A3 + ACE3*: AI with basic self-treatment and medic behaviour (ACE AI medical).

**Standing.** Ahead: real items from the casualty's own kit, no full heal, smoke and drag before
treating. Lifeline's AI never drags or carries. Open items from the Oct 14 AI gap list (they may
have closed since): no cap on how many leave the fight for casualties, and casualties aren't ranked
by how bad they are.

### 2.5 Medical menu and lasting injury
**Now.** An ACE-style medical menu (H): body diagram, treatment tabs, signs in words, an activity
log and triage cards. A HUD silhouette shows while you bleed. Body interaction points. Injuries
cost days out of action back at base, and the medbay shortens that for money. Wounds are kept
across zone crossings and when a save is resumed.

**Compared with.**
- *A3 + ACE3*: the medical menu Contractor's is inspired by.
- *Escape from Tarkov*: health screen per limb, and injuries that carry out of the raid.
- *Ready or Not (Commander mode)*: officers' injuries and stress carry across missions.

**Standing.** On par with ACE3 for the menu, and ahead on how long injuries last in the campaign.

---

## 3. Squad AI and command

### 3.1 Scored-intent squadmates with real fire-team drills
**Now.** Each AI picks from scored intents every half second, with hysteresis. It takes cover that
actually blocks the threat, preferring concrete and sandbags. Buddies bound with "Moving!" and
"Covering!". A squad-level evaluator picks between holding, suppressing and flanking (base of fire
keeps the autorifleman), assault, clearing or defending a building, breaking contact with smoke,
and searching. It never fires through a friend, frags only with a clear arc, and spotting takes
time (camo in CIE Lab against the ground, foliage, stance, muzzle flash, optics).

**Compared with.**
- *Arma 3 (Veteran) + LAMBS Danger + VCOM*: the Captain's bar. LAMBS clears and garrisons
  buildings and suppresses; VCOM flanks, uses cover and calls reinforcements.
- *Ready or Not*: SWAT AI that stacks, breaches and clears rooms well indoors.
- *Ghost Recon Wildlands / Breakpoint*: three AI teammates who are effective but simplified
  (sync shot, they are hard to spot).

**Standing.** Ahead of the Arma stack on fairness: spotting takes time, real camo and foliage
count, aim has a turn-speed cap, and VCOM's flanks leave no base of fire behind, where Contractor's
do. Behind on breadth (per the Oct 14 gap list): the AI doesn't choose to go prone, assaults run
rather than bound, there's no instant reaction to a near miss, and it targets the nearest enemy
rather than the most dangerous.

### 3.2 Arma-style command menu, colour teams, formations, combat modes
**Now.** F1 to F8 per slot, with number keys or the mouse wheel: move, bound, take cover, fall
back, garrison, clear, focus fire, suppress, watch a sector, open or hold fire, stance, mount,
status, smoke or frag there, launcher, gear (rearm from a body, scavenge, give me ammo, drop packs),
casualties, climb, Safe/Aware/Combat/Stealth, four formations, and fire teams with colour teams. An
order that can't be done says why. Any player can give orders, and the last one to do so leads.

**Compared with.**
- *Arma 3*: the F-key and number command menu, with colour teams and behaviour modes that
  Contractor's are in the spirit of.
- *Ready or Not*: a context command wheel with gold and blue teams.
- *Ghost Recon Wildlands*: four simple orders (regroup, hold, go to, open fire).

**Standing.** On par with Arma for depth, and ahead on feedback (orders say why they fail; Arma's
fail silently). Squad-level tactic orders (clear that building, bound there) are richer than the
vanilla menu.

### 3.3 Voice orders, questions and context-aware callouts
**Now.** Push-to-talk (T) maps a bounded set of phrases onto command-menu keys, and you can ask a
friendly or civilian a question that they answer from their live state. No speech recogniser is
wired yet: holding T opens a text box. Callouts are voiced with Piper TTS and give contact
direction and range ("Contact, two o'clock, 80 m"), intel finds and ammo state. Enemies speak in
their own language.

**Compared with.**
- *Ready or Not*: officers' voice lines, plus third-party voice-command mods.
- *Arma 3*: voiced radio protocol for contacts and orders, plus voice-control mods.
- *Ground Branch*: a basic friendly-AI order set (Fall In, Hold, Move and Clear, Take Cover) as a
  first pass.

**Standing.** Ahead on answers drawn from live state and on contact callouts. Behind until a real
offline recogniser is in: today it's typing.

### 3.4 Need-based scavenging and logistics
**Now.** Out of contact, an AI that is short of something searches a body one item at a time: ammo
its gun takes, then missing medical items, then grenades. It takes armour only when well out of
contact and only if clearly better. It respects a 35 kg limit and never touches a dead player's
body. Ammo bearers resupply belt-fed gunners, and squadmates share ammunition. Enemies follow the
same rules.

**Compared with.**
- *Arma 3*: the AI can be ordered to rearm from a body, but doesn't decide to on its own.
- *Escape from Tarkov*: Scav AI loots bodies and containers.
- *Jagged Alliance 3*: mercs share inventory through the sector stash, managed by the player.

**Standing.** Ahead: no other game here has squadmates that choose by need what to take. Simpler:
item by item from bodies only, not from crates or vehicles.

### 3.5 AI that digs in, climbs, and drives
**Now.** A squadmate holding a spot out of contact digs a berm in front of it. On order,
squadmates climb walls and onto roofs. They take the wheel of the squad's vehicles: drive there,
convoy behind the commander, come pick us up, stop, and dismount on contact (on by default). They
use the zone's roads when that's the better way. The map takes "Our drivers: drive here".

**Compared with.**
- *Arma 3*: AI drivers and convoys, famously unreliable on roads and in towns. ACE3's trenches are
  player-dug.
- *Arma Reforger*: AI vehicle use is still limited (community feedback asks for better get-in and
  get-out and pathing).
- *Ghost Recon Wildlands*: AI teammates ride along while the player drives; they don't take
  driving orders.

**Standing.** Ahead on contact dismount and AI that digs on its own. Unproven: this is new (part 1
and part 2 landed 2026-10-19) and hasn't been playtested on long routes. Vehicle pathing uses
straight roads and the navmesh, without traffic rules or formation spacing on curves.

### 3.6 High command: allied elements and hired company squads
**Now.** Allied rifle squads (8 men) and weapons teams (M240B, ammo bearer, two AT4s) come in
through the support menu, in their nation's kit (US M4, UK L85A2, Canadian C8). The host commands
them with general orders and map orders (move, mount, drive, dismount). Hired company squads and
base guards sit under the same high command.

**Compared with.**
- *Arma 3*: the vanilla High Command module (map waypoints for groups). The design docs also cite
  a "Platoon Commander" mod (not verified here).
- *Arma 3 + ALiVE*: player-requested reinforcements and group tasking within a persistent
  campaign.

**Standing.** On par with Arma's High Command for the basics, and ahead in that these are paid
company assets that persist. Missing: the hero squad leaders design (named roster members leading
their own squads, orders with a lifecycle and report-back) is a proposal only. The map order set is
small.

---

## 4. Enemy AI

### 4.1 Honest alert and information sharing
**Now.** The enemy knows only what its people see, hear and radio in. Reports take time, a man
killed first never reports, the last known position grows less certain, and areas cool down
slowly. There's no on-screen meter. A downed comms mast slows the net. Heard shots carry position
error. Patrol looks merge per contact.

**Compared with.**
- *Arma 3 + LAMBS / VCOM*: knowledge is shared across groups at once (the "hive mind" players
  complain about).
- *Gray Zone Warfare*: players report a sixth sense and instant position sharing.
- *Ghost Recon Wildlands*: an alarm system and reinforcements once alerted.

**Standing.** Ahead: this is the fix modders apply to Arma and Reforger, built in from the start.
Still open (Oct 18 research): contact reports between squads should arrive with a delay and an
error that depend on the reporter.

### 4.2 Pressure, QRFs, hunters and trackers
**Now.** Firefights, kills and objectives earn pressure, which falls when it's quiet. Its tiers
double patrols, launch QRFs from QRF bases (often riding technicals), send hunter teams that flank
and use smoke, and reinforce the HQ. Trackers pick up the squad's trail, fire signal shots and
follow it; roads, water and dog-legs break the trail. Nothing spawns in sight, and waves come from
350 m out or more.

**Compared with.**
- *S.O.G. Prairie Fire (Arma 3)*: the Tracker module (trail following, signal shots).
- *Arma 3 + VCOM*: reinforcements called in proportion to the threat.
- *Ghost Recon Wildlands*: Unidad reinforcements escalating with your notoriety.

**Standing.** On par with SOG's trackers, and ahead on escalation tied to what the enemy actually
knows. Missing: no mines or traps the player can leave on the trail, and no enemy artillery or
mortars (G-25).

### 4.3 Enemy high command
**Now.** In hot zones a commander judges the squad through the fog of its own reports. It has
finite reserves that refill slowly, hunts only at 2:1, contains or counterattacks lost sites at
3:1, probes stale positions, reoccupies sites, consolidates, and can be deceived (noise draws
probes; a looted radio can fake contact reports). The commander is a real, huntable soldier with
bodyguards; killing or capturing him leaves the zone headless. His memory carries across
deployments.

**Compared with.**
- *Arma 3 + ALiVE*: OPCOM commanders that run objectives across a map, with persistent force
  pools.
- *Arma 3 + VCOM*: reinforcement logic with per-area cooldowns.
- *Ghost Recon Wildlands*: cartel bosses you remove to collapse a region, as a story structure.

**Standing.** Ahead of ALiVE on fog (OPCOM knows more than it should) and on a commander you can
kill in person. Simpler: one zone at a time (ALiVE runs a whole island), and no air or artillery
assets for it to spend.

### 4.4 Garrisons, ambushes, IEDs, bombers, drones
**Now.** Compound garrisons hold their walls: they ambush inside, and break and run when
outgunned. Outposts are dug in. Roadside IEDs make a contract's "IEDs" threat real. Insurgent
factions send suicide bombers on foot (the tells: no rifle, heavy vest, straight walk) and VBIED
technicals. In hot zones the enemy flies recon quadcopters that report the squad; shoot them down
or carry a jammer.

**Compared with.**
- *Arma 3 / Reforger* (mission makers' tools): IEDs, VBIEDs and drones by script or mods, not
  systemic.
- *Ghost Recon Breakpoint*: enemy drones that patrol and report.
- *Escape from Tarkov*: no comparable threats; AI raiders and bosses with guards instead.

**Standing.** Ahead: these are systemic and come from a faction's kit and heat, not hand-placed by
a mission maker. Simpler: patrols themselves don't set ambushes in the open (G-26), and the AI
doesn't avoid ground that's being shot up.

### 4.5 Factions fighting each other, rival PMC, named hunter squads
**Now.** Factions at war send teams to hit each other's garrisons while the squad is out. A
faction the company gets on with leaves it alone; a hostile one shoots everyone. The Vantage Group
(a rival PMC) races the squad to contract sites and fails the contract if it holds the site first;
at higher difficulty it fields LX-3 and HX-1 exosuits. Heat with a faction brings hunter squads,
and past a threshold named hunter squads that get better at every meeting until their leader dies.

**Compared with.**
- *Middle-earth: Shadow of Mordor*: the Nemesis system (named enemies who remember you), which
  inspired the named squads.
- *STALKER (A-Life)*: factions fighting each other off-screen and on.
- *Ghost Recon Breakpoint*: Wolves patrols hunting the player.

**Standing.** Ahead for a milsim: none of the Arma-family games has nemesis-style hunters or a
rival contractor race built in. Simpler: these are first slices, and hunter squads' "memory" is a
skill ramp, not personal traits or taunts.

### 4.6 Morale, surrender, enemy medics
**Now.** Morale per soldier falls with losses, wounds, suppression and odds, and comes back when a
leader is near. A broken soldier falls back; a broken hostile seen alone may surrender and be
cuffed. Enemy medics treat where they can, but fight before nursing.

**Compared with.**
- *Arma 3*: group-level fleeing only. LAMBS adds some panic.
- *Ready or Not*: suspects surrender based on compliance and morale.

**Standing.** Ahead of Arma per soldier. On par with Ready or Not for surrender.

---

## 5. Campaign and the company

### 5.1 Persistent roster with permadeath and MIA
**Now.** Each hire is rolled once as a whole person (name, nationality, hand, body) with skills
(aim, nerve, medical, movement), XP, a wage that grows, their own gear, and a history of injuries.
AI death is permanent. A squadmate left alive behind goes MIA, and a recovery contract finds him
where he was left. Players respawn in the kit they died in, from a pool of free respawns per
deployment, then paid ones.

**Compared with.**
- *Jagged Alliance 3*: mercs with personalities, daily wages and contracts, injuries and death.
- *Ready or Not (Commander mode)*: a roster, officer permadeath, and stress that needs therapy.
- *MechWarrior 5*: pilots with skills, injuries and pay.

**Standing.** On par with Ready or Not for permadeath, and ahead with MIA and recovery contracts.
Behind JA3: no personalities, likes and dislikes, or lines that make hires memorable.

### 5.2 Reputation, heat, and a faction war between missions
**Now.** Reputation with each faction runs Hostile, Distrusted, Neutral, Trusted, Allied, and
unlocks allied quartermasters and troops. Heat with a faction brings hunters, then patrols, probes
and assaults on the base. A persistent world: each hot zone has a holder and a grip; contracts won
knock the grip down; weak zones flip between days, which posts flashpoint contracts. Contracts can
understate the threat when intel is poor.

**Compared with.**
- *Arma 3 + ALiVE*: a persistent campaign with sector control and moving fronts.
- *MechWarrior 5*: faction reputation that unlocks contracts and better negotiation.
- *STALKER*: faction standing and an offline A-Life that moves factions.

**Standing.** On par with ALiVE's persistence at a smaller scale, and ahead of MW5 on a world that
moves without you. Simpler: three playable-side employers and five enemy or allied factions. The
war is grip numbers on a region map, not simulated battles you can watch.

### 5.3 Rebel support, per region (in the spirit of Ghost Recon Wildlands)
**Now.** The locals' backing (0 to 100 per region) rises when you treat civilians and kill
hostiles near villages, and falls with civilian casualties and heat. Its tiers unlock call-ins:
lookouts (enemies tagged for you), a diversion, rebel fighters under high command, a vehicle drop,
and a mortar. They work in hot zones too, but weaker. The locals' own jobs (clear the checkpoint,
find a missing villager, the stolen stores) come on the board and from asking villagers, paid in
support and favours; villagers also take medical supplies.
Upgrades bought with favours are designed, not built.

**Compared with.**
- *Ghost Recon Wildlands*: rebel supports (vehicle drop, diversion, mortar, recon, backup) unlocked
  and upgraded through side missions.
- *Jagged Alliance 3*: training local militia to hold sectors.

**Standing.** On par with Wildlands on the call-ins. Ahead in that support is earned through how
you treat people, and lost the same way. Behind until the local tasks and upgrades land.

### 5.4 Hot zones: several contracts, radio follow-ups, hazard pay
**Now.** A hot zone keeps 3 to 6 contracts live. What the squad does brings new ones over the radio
("you hit their QRF, now hit the HQ"), including capturing the enemy commander. Staying longer pays
more. The employer tips you off when the enemy masses a counterattack.

**Compared with.**
- *Gray Zone Warfare*: a persistent open map with tasks from vendors.
- *Arma 3 + ALiVE*: dynamic tasking on a live map.
- *Ghost Recon Wildlands*: open-world provinces with chains of missions.

**Standing.** Ahead on missions that react to what you did. Simpler: generated briefs and a small
set of objective types, without story missions or hand-made set pieces.

---

## 6. Base building

### 6.1 The base as an explorable zone, with threats
**Now.** The FOB is a module in a full contract-size zone of its own: a helipad, a vehicle park, a
range, villages, an abandoned compound and outpost to scavenge, and edge crossings. Heat brings
patrols to the far area (heat 30+) and probes on the wire (50+). Assaults (70+, at most one a week)
are announced a day ahead. You fight them live at the base, or the base holds out while the squad
is within two links and comes back, or they resolve off-screen with stash losses and a situation
report.

**Compared with.**
- *Escape from Tarkov*: the Hideout. A menu base that's never attacked.
- *Gray Zone Warfare*: a walkable faction base you fly out of, never attacked.
- *DayZ*: player-built bases raided by other players.

**Standing.** Ahead: a base you can walk and that the enemy you angered comes for, with off-screen
resolution, is rare in this genre. Simpler: the FOB itself is a fixed compound that grows by tier,
not a free-form layout.

### 6.2 Defences, guards, tiers, hired squads
**Now.** Bought at the ops desk: watchtowers, an MG pit, a HESCO chicane, a bunker, a mortar pit,
and ground sensors (which radio a direction and range for hostiles within 300 m). Placed at set
slots, or freely with a placement tool on the zones' 12 m grid. Hired guards are on the wire. FOB
tiers cost $40k and $120k and raise guard counts and defence choices. Hired company squads go
under high command.

**Compared with.**
- *Arma Reforger (Conflict)*: building compositions at bases with supply points.
- *Squad*: FOBs with HABs and shovel-built emplacements from construction supplies.
- *Arma 3 + ACE3 Fortify*: placing fortification objects from a budget.

**Standing.** On par with Reforger and Squad for placing things, and ahead in that defences matter
when you're away (they count in the off-screen result). Simpler: a small catalogue on a 12 m grid
(no walls by the segment). The player can't build forward FOBs in other zones by design (the
Captain's 2026-10-11 call); wave 8's player-built faction is design only.

### 6.3 The LHD and the motor pool
**Now.** On the coast, an LHD offshore launches AAVs and helicopters. The motor pool holds the
company's vehicles with service, repair and fuel. Air wing upgrades: the Razorback heavy VTOL, an
armoured cabin, and fast-turnaround crews.

**Compared with.**
- *Arma 3*: the USS Liberty / Freedom as mission-maker assets.
- *MechWarrior 5*: the dropship as a mobile base, and mech bay repairs.

**Standing.** On par as a home-base fixture. Simpler: the LHD is a launch point and a set of
terminals, not a walkable ship.

---

## 7. Economy and contracts

### 7.1 Contract board and MW5-style negotiation
**Now.** A seeded board always offers one low-risk job, and fixers offer special jobs once your
reputation is high enough. Hold up to 4; letting one lapse costs reputation. Negotiate pay against
salvage share, support budget and a 30% advance. Clawback terms apply on a void. Renegotiate or
abort once the real threat shows. 13 contract types: raid, HVT capture, hostage rescue, intel grab,
convoy ambush, defend and hold, downed crew rescue, sabotage, recon, client escort (PSD), and three
that cross zones: supply line, manhunt and convoy chase.

**Compared with.**
- *MechWarrior 5*: contract negotiation over C-Bills, salvage and damage cover, which Contractor's
  learns from.
- *Jagged Alliance 3*: sector contracts and mission briefings.
- *Ghost Recon Wildlands*: mission variety across an open map.

**Standing.** On par with MW5's negotiation, and ahead on understated threat and renegotiating in
the field. Simpler: the objective types are still a modest set (playtest feedback on 2026-10-15
was "boring"; five types have been added since).

### 7.2 One bank, wages, upkeep and real expenses
**Now.** One bank, with a ledger and a campaign clock in days. Weekly wages and base upkeep, field
costs per person per day, a death benefit per KIA, care per wounded, priced support calls, $30k to
$40k to replace a lost helicopter, emergency and manual loans. A standard contract nets about 30 to
45%, and a disaster goes about $75k negative. The debrief shows "where the money went".

**Compared with.**
- *Jagged Alliance 3*: daily merc fees and mine income, where money gets tight.
- *MechWarrior 5*: monthly operating costs, repairs and pilot salaries.
- *Escape from Tarkov*: a raid economy of gear lost and bought back, plus insurance.

**Standing.** On par with MW5 and JA3 for pressure. Still being tuned: the 2026-10-16 note says
"too easy overall, but mission expenses swing it negative fast". No passive income (JA3's mines)
beyond selling salvage.

### 7.3 Loot, salvage, pallets, quartermasters, the shop
**Now.** A loot window with search time (in the spirit of Tarkov's): two panes and a server-checked
move per item. Rarity loot boxes in compounds, and valuables and intel placed with common sense.
World caches. Supply pallets at enemy sites can be tagged to sell or as a gift to a faction; after
extraction you sell now at 50%, store, or keep for the FOB's stocks. Allied quartermasters sell
their kit, armour and MRAPs by your standing. The shop has search and sells from the stash.

**Compared with.**
- *Escape from Tarkov*: search time, traders with loyalty levels, and the flea market.
- *Gray Zone Warfare*: vendors with reputation that gate gear.
- *Ghost Recon Wildlands*: supply caches you tag for the rebels.

**Standing.** On par with Tarkov's trader-by-loyalty idea, and ahead with pallet tagging as
logistics. Simpler: no player market, item prices are fixed, and the FOB arsenal stash doesn't use
the loot window yet.

---

## 8. The world

### 8.1 Voxel destruction at 10 cm
**Now.** Structures are 10 cm voxels with 18 regional materials, plus sandbags and HESCO. Wood and
sheet metal take round-sized holes and break out after 10 to 16 rounds; concrete cracks. Frags,
charges and launchers carve holes, craters and breaches. Damage is shared with every player and
saved. Navigation updates around a breach in a fraction of a second.

**Compared with.**
- *Teardown*: fully destructible 10 cm voxel worlds, with structural collapse and physics debris.
- *Arma 3 / Reforger*: buildings swap to destroyed models, without free-form holes.
- *Ready or Not*: destructible doors and some breakable cover.

**Standing.** Ahead of every milsim here: real breaching anywhere, persistent, and AI that paths
through it. Behind Teardown: no structural collapse or physics debris, and voxel art is still
placeholder-level in places.

### 8.2 Procedural zones, terrain presets and generated buildings
**Now.** Seeded contract zones of 2 to 4 km² and hot zones of 16 km² (an HQ, a comms site, QRF
bases, outposts, checkpoints, villages, roads), with urban hot zones. 22 contract zones and 5 hot
zones on a region map. Terrain presets (temperate, coastal, salt flats, desert wadi, rocky ridge,
scrubland, forest). Buildings are generated: a shell, rooms by type (house, shop, warehouse,
clinic, police station), interior chunks, storeys and stairs, the same on every visit. Landmarks
(queue item 1.4): an office, a mosque, a church, a school, a garage, a fuel station, a factory, a
farm, a harbour with piers and cranes, an airfield with hangars and a tower, an oil field, a fuel
depot, and the terror groups' drug labs and IED workshops, each with ruined and bombed-out
variants, placed in the zones their asset tags name. Modules stream in at 260 m, with stand-ins
out to 2.5 km.

**Compared with.**
- *Arma 3 / Reforger*: hand-made maps of 50 to 270 km².
- *Ghost Recon Wildlands*: a large hand-made open world.
- *Teardown*: hand-made voxel levels.

**Standing.** Ahead on variety: every zone is generated and every building can be breached and
furnished. Behind on scale and authored detail: zones are a few km², and generated landmarks are
simpler than a hand-made map's set pieces. City zones (phase 4) aren't built.

### 8.3 Linked zones, crossings, zone memory and raids (in the spirit of STALKER)
**Now.** Zones join on a region map through marked crossings at their edges. Everyone and
everything in a crossing goes through: players, squadmates with their wounds, HVTs, vehicles,
helicopters, the AAV and allied elements. Travel time runs on the clock, and wounds tick on the
way. A zone you leave remembers you and fades back to fresh over a week, while the enemy
reoccupies. Raids: going out without a contract to scavenge and hit sites, with lean rules (2 free
respawns, no pay). Contracts can be left and returned to. Save while out and resume at the last
crossing.

**Compared with.**
- *STALKER: Shadow of Chernobyl / Anomaly*: separate levels joined by transitions, with A-Life
  running offline on the levels you're not on.
- *Escape from Tarkov*: separate maps, with transits between some of them (added in 2024).
- *DayZ*: one big persistent map instead.

**Standing.** On par with STALKER's structure, and ahead on what crosses with you (supports,
vehicles, wounded people). Simpler: only one zone is live at a time for the whole group; split
squads wait for dedicated servers. Zones you're away from only fade or flip grip, without
STALKER's simulated NPC lives.

### 8.4 Digging: berms, foxholes, trenches and craters
**Now.** An e-tool digs a fighting position in about 20 s: a berm of earth in the ground's own
colour that stops rounds and wears down under blasts. Digging again makes the foxhole deeper, and
digging beside it runs it into a trench. Explosions leave real craters in the terrain (a fine
0.25 m grid over the 4 m ground). The AI digs in on its own, and enemy outposts have their
parapets up before you arrive. All of it is saved with the zone.

**Compared with.**
- *Arma 3 + ACE3 trenches / GRAD Trenches*: entrenching-tool trenches. GRAD deforms the terrain.
- *Squad*: shovel-built emplacements, not terrain cuts.
- *Teardown*: everything is diggable voxels, including the ground in many levels.

**Standing.** Ahead of the Arma mods: craters from blasts, and AI that digs. Simpler than
Teardown's fully voxel ground: the cuts are a height field, so no tunnels or overhangs.

### 8.5 People: civilians, HVTs, hostages
**Now.** Civilians follow daily routines and flee, hide and cower under fire. Fines for civilian
casualties, and the 8th voids the contracts. Hostile HVTs try to expose the squad and run until
zip-cuffed, and you escort, carry or seat them in a vehicle. Intel items open leads. Plain clothes
by region and role.

**Compared with.**
- *Ready or Not*: civilians and suspects with compliance; arrest and restraint.
- *Ghost Recon Wildlands*: civilians in towns, and interrogating targets.
- *Arma 3*: civilians via modules (ALiVE adds civilian activity).

**Standing.** On par with Ready or Not for handling HVTs, and ahead on the cost of civilian harm in
the campaign. Simpler: there are no compliance shouts, and civilians' lives are routines, not
simulated needs.

---

## 9. Supports

### 9.1 Helicopter and VTOL supports
**Now.** Resupply, transport (anywhere since LZ-3, and between zones), extraction, and insertion by
hot drop or fast-rope. Mark by grid, the spot under your crosshair, or a smoke colour; the aircraft
loiters until it sees the smoke. The VT-14 Petrel VTOL (a .50 belly turret), the Razorback heavy
lift, and the UH-60 with a walk-in cabin and door gunners. Each airframe keeps its fuel and damage
between calls. Storms ground them. Lost aircraft cost money and are gone for the op.

**Compared with.**
- *Arma 3*: support modules (transport, supply drop, CAS, artillery); mostly player-flown.
- *Gray Zone Warfare*: helicopter insertion and extraction from the base to set LZs.
- *Squad / Arma Reforger*: player-flown transport helicopters.

**Standing.** Ahead on smoke-marked calls, airframes that keep their state, and AI pilots who fly
low and make J-hook landings. Behind: players can't fly (aircraft are AI-flown only), and there is
no close air support or attack helicopter run (the AH-1Z exists as a model).

### 9.2 AAV from the LHD, allied troops, rebel call-ins, mortar pit
**Now.** An AAV-7 swims in from the LHD (or drives in from the FOB side) to move, hold, follow,
take troops and fire its M2. Allied elements under high command (6.2 and 3.6). Rebel call-ins
(5.3). At the base, a mortar pit counts double on the wire.

**Compared with.**
- *Ghost Recon Wildlands*: rebel supports.
- *Squad*: commander assets (artillery, UAV) on a cooldown.
- *Arma 3*: artillery and CAS support modules.

**Standing.** Ahead on combined, persistent assets that cross zones with you. Behind: no player
artillery, CAS or UAV call yet beyond the rebel mortar.

### 9.3 Tagging enemies by radio (in the spirit of Ghost Recon Wildlands)
**Now.** Look at a visible enemy and tag him, keying the radio on your carrier (an animation). For
a while his whole side sees a red mark through walls and on the map, and the squad's AI knows
where he is. A radio is required, and binoculars or an optic help. Rebel lookouts tag the same way.

**Compared with.**
- *Ghost Recon Wildlands / Breakpoint*: drone and binocular tagging, with marks through walls.
- *Squad / Arma*: map markers and spotting by voice, without through-wall marks.

**Standing.** On par with Wildlands, with a radio requirement as the grounding. No drone of your
own yet.

---

## 10. Vehicles

### 10.1 Drivable vehicles with voxel hulls and real penetration
**Now.** 14 voxel vehicle models: UH-60, AH-1Z, AAV-7, MaxxPro, M-ATV, Bradley, Abrams and seven
technicals. Physics with suspension: wheeled vehicles steer, tracked ones skid-steer. Hit zones
(hull, engine, wheels or tracks, fuel, crew, cargo) and penetration by class: small arms bounce,
7.62x54R and up penetrate MRAPs, and a round that gets through goes on into the crew. Hits carve
and scorch the voxel hull. Fires, wrecks to salvage, timed field repairs, fuel and jerrycans, cargo
in litres and kg, and mounted M2/DShK fed from cargo. MRAPs can be bought from allied
quartermasters.

**Compared with.**
- *Squad*: component damage, and vehicle armour by facing and thickness.
- *Arma 3 / Reforger*: wide vehicle sets with hit-points per part, repairs and fuel.
- *Teardown*: voxel vehicles that break apart.

**Standing.** Ahead on visible voxel damage and on rounds carrying into the crew. Simpler: few
models; turning turrets exist only on the M-ATV, MaxxPro, AAV-7 and technicals
(`vehicle_turret.gd`), so the Bradley's and Abrams' main guns aren't crewable; and no flyable
aircraft.

### 10.2 Exosuits: the LX-3 Assist Frame and the HX-1 Assault Frame
**Now.** The LX-3 is a light infantry exo that carries 30 kg of your load, with twelve Steel III++
pads and a visor helmet; its struts can be shot until it fails. The HX-1 is a heavy frame you climb
into: fifteen real armour plates, a .50 BMG Walker Gun, 80 kg of kit, never sprints or goes prone.
A downed pilot can be punched out. Vantage fields both at high difficulty.

**Compared with.**
- *MechWarrior 5*: piloted mechs (much bigger and vehicle-scale).
- No close milsim match among the games listed. Arma 3, Reforger, Tarkov and Gray Zone have no
  wearable exos.

**Standing.** A distinctive near-future touch, with real per-plate armour. First slices only: the
HX-1 isn't sold yet, and balance is untested.

---

## 11. Co-op and netcode

### 11.1 Four-player co-op, host-authoritative
**Now.** Up to 4 players on a listen server over ENet, with the host authoritative (requests are
checked before anything is spent). Late joiners see everything: voxel damage, smoke at its age,
bodies, carried bodies, markers and rounds in flight. Other players' movement is smoothed. AI fills
the rest of the 8 slots. Host-set co-op assists (aim slowdown for the stick, wound hints).

**Compared with.**
- *Ghost Recon Wildlands*: 4-player drop-in co-op.
- *Ready or Not*: 5-player co-op.
- *Arma 3 / Reforger*: dedicated servers for dozens of players (100+ with headless clients).

**Standing.** On par with Wildlands and Ready or Not for party size, and ahead on late-join state
of a destructible world. Behind Arma: no dedicated server, no headless client, no PvP, one zone
live at a time, and no server browser or matchmaking found.

### 11.2 Saves, persistence and performance
**Now.** Zones save looted and dropped items, voxel and ground damage, bodies, vehicles and fallen
posts, written safely with a backup. Dynamic simulation (in the spirit of Arma's): AI far from
every player sleeps in place and costs nothing on the net. Buildings are drawn in 32-voxel mesh
blocks, and there's an in-fight phase profiler.

**Compared with.**
- *Arma 3*: dynamic simulation, and ALiVE's profile virtualization.
- *DayZ*: persistent server-side world.

**Standing.** On par with Arma's dynamic sim, and ALiVE-style virtualization is built
(`docs/virtualization.md`, 2026-10-18): far enemies become profiles that move, fight and garrison
off-screen, and come back as men out of sight. Dynamic sim stays for what isn't virtualized
(vehicle crews, bombers, the rival PMC team and scenario waves).

---

## 12. UI and onboarding

### 12.1 In-game tutorial
**Now.** A solo session on the compound with a panel that walks through the controls one step at a
time, showing the live key bindings, ticking itself off as you do each step, with a stand-in target
across the yard. Its sections go past the controls (2026-10-20): gear and MOLLE, squad orders,
treating yourself and calling a medic, dragging and tourniqueting a casualty, vehicles, rebel
support, static guns, and short steps to read on the campaign loop. A section list lets a player
skip what a teammate will teach them.

**Compared with.**
- *Arma 3 / Reforger*: the Bootcamp campaign and Reforger's training scenario.
- *Ready or Not*: a training range at the station.
- *Ground Branch*: a practice range.

**Standing.** Still simpler than Arma's Bootcamp, which it learns from: it now plays a medical
scenario and vehicles, but explains the campaign loop rather than playing it, and teaches no
tactics yet.

### 12.2 Map, briefing, extraction and debrief
**Now.** A map (M) with a grid, shared markers and lines, intel positions and objectives. An
Arma-style briefing with plan marks, the insertion side and ready-up. Extraction at an LZ, a grid
reference or purple smoke, with the two-confirm leave-behind rule. The debrief shows pay, salvage,
casualties, reputation, tagged lots and expenses. A region map on the ops desk.

**Compared with.**
- *Arma 3*: a briefing map with markers, and a map without GPS.
- *Jagged Alliance 3*: a strategic satellite view.
- *MechWarrior 5*: a post-mission salvage screen.

**Standing.** On par. The debrief is more detailed than most.

### 12.3 Inventory, MOLLE, loot window, medical menu, controller
**Now.** Inventory in litres and kg with a turnable 3D preview. MOLLE points on carriers (6, 9 or 12
by type) with typed pouches, and gear visible on the body. The loot window (7.3) and the medical
menu (2.5). Full gamepad layout with a pad wheel. A shared UI theme fitted across ten resolutions.
A compass strip.

**Compared with.**
- *Escape from Tarkov*: grid inventory with rigs and containers.
- *Star Citizen*: physical inventory with armour and backpacks on the body.
- *Gray Zone Warfare*: Tarkov-style grid with chest rigs.

**Standing.** Ahead on MOLLE placement that you can see on the body. Simpler: litres instead of
Tarkov's spatial grid (a design choice).

### 12.4 Developer and feedback tools
**Now.** A bug-report key saves a numbered folder (a note, a screenshot, every soldier's state and
AI intent, the seed, the last log lines). Numbered session logs. An AI overlay. Numbered test runs
that are never deleted, and 44 suites in CI.

**Compared with.** Arma 3's debug console and diagnostic tools for mission makers, and the Ground
Branch and Reforger workbenches.

**Standing.** Ahead of most indie peers on tools for reporting playtests. Not a player-facing
feature, but it's why the AI and medical systems can move as fast as they do.

---

## Not verified

- **Ground Branch friendly AI.** A 2024 developer report gave V1035 a first pass at AI teammates
  (Fall In, Hold, Move and Clear, Take Cover; breach not working). A third-party source says full
  friendly AI is planned for Chapter 1 (V1.1.0). Whether it has shipped couldn't be confirmed.
- **Arma Reforger.** No official confirmation was found of AI squad recruitment in Conflict, or of
  how much free-form destruction 1.x has. The comparisons here stick to Conflict's supplies and
  base building, which are confirmed.
- **"Platoon Commander" for Arma 3** is named in `docs/linked_zones.md`; the mod's exact name and
  features weren't checked.
- **Tarkov's transits between maps** (2024) are from memory, not checked again.
- **Contractor's AI gaps** come from the 2026-10-14 list (`docs/ai_bar_gaps.md`). Some may have
  closed since without the list being updated.

## Summary

- **Distinctive now:** the medical model (ahead of ACE3 + KAT); voxel armour and 10 cm voxel
  breaching in a milsim; fair AI (timed spotting, real camo, delayed radio reports) with fire-team
  drills; an enemy commander working through fog.
- **Also distinctive:** a company campaign that combines MW5-style contracts, JA3-style money
  pressure, STALKER-style linked zones, a base the enemy comes for, and supports that cross zones
  with you.
- **Biggest gaps:** placeholder art and animation against Star Citizen-level feel; 4-player listen
  server only (no dedicated server, one zone live); aircraft you can't fly, and no CAS or artillery.
- **More gaps:** small zones and a modest set of mission types; AI breadth items (going prone,
  near-miss reactions, choosing the most dangerous target); voice orders still typed; economy and
  most numbers not yet tuned by playtests.
- **Would most improve standing:** real art and motion, especially weapons, characters and
  animation; a dedicated server with split squads; closing the P0 and P1 AI gaps against the
  LAMBS/VCOM bar; finishing rebel tasks and upgrades and the hero squad leaders; then fire support
  and player-flown aircraft.
