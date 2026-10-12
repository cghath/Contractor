# ChrisPlan handoff: everything left, ready to pick up

**For:** Noah (Captain's side) and any agent working with him. **From:** cghath (Chris) and
his agent, 2026-10-11, with `dev` at 7ec6fd0 (all 20 suites passing).

This is cghath's side's plan for the rest of the build, written so any part can be picked up
without asking. The rules and numbers stay in the design doc and
[contractor_handoff.md](contractor_handoff.md); the wave order and agent rules stay in
[build_plan.md](build_plan.md). Wave 4B has its own detailed handoff:
[wave4b_handoff.md](wave4b_handoff.md).

**If you take a wave or a piece of one, mark it in build_plan.md ("Captain's side" with the
date), as with wave 3, so both sides never build the same thing twice.**

## Where things stand

| Wave | State | Notes |
|---|---|---|
| 0 Prep, 1 Phase 3 core, 2 Phase 3 finish | Done, on `dev` | Playtest fixes from Captain's two playtests are in |
| 3 Medical depth | Done by Captain's side | cghath's own wave 3 was dropped (kept on a local branch only); its extras are listed under Backlog |
| 4A Mission loop, first half | Done, on `dev` | World scale, contracts and economy, people, base hub and roster, map/briefing/extraction, one join handshake |
| **4B** Wire the loop, hot zone | **In progress, Captain's side**: parts 1 and 2 on `dev`; part 3 (hot zone) in progress | [wave4b_handoff.md](wave4b_handoff.md) |
| 5 Vehicles and supports | **Starting on cghath's side (2026-10-12)**, see the note under Wave 5: the base hub stays as is until wave 5 makes it the first friendly FOB | AH-1Z, MRAPs, Bradley, Abrams: the US and the close allies that operate them (Captain, 2026-10-11) |
| 6 Factions | **Blocked on Captain** | Needs the decisions listed below |
| 7 Art, world and weapons | Systems half planned below | Art waits for Captain's asset scripts; Stormworks-style characters in progress on Captain's side |
| 8 Player-built faction | Design proposal only | |

## How a wave runs (what has worked)

1. **Spec first.** Per workstream: the files it owns, the interfaces it uses or provides
   (exact class and function names), the checks that prove it. Give each workstream its own
   new test suite and its own test tag and port.
2. **Parallel builders in git worktrees**, one branch each, then a **reviewer** per branch
   that reruns every suite, then a **fix** pass only if the reviewer finds blockers or majors.
   Five at once is the ceiling that worked.
3. **Small shared groundwork before the wave** (an interface stub, an autoload, a data
   section) so parallel agents build against the same names. Wave 3's heart-rate stub and
   wave 4's `Campaign` autoload and `map_area()` were enough to keep five branches mergeable.
4. **Merge, then run every suite**, then fix integration bugs. The seams between parts are
   where the real bugs were (4A: two join handshakes fighting; a client's spawn position).
5. **Docs** (CHANGELOG under Unreleased, README controls/tests/known gaps, build_plan status,
   handoff checklist), **a dated build** (`tools/make_build.sh <label> "<what to test>"`),
   then push `dev` as a fast-forward. cghath's side summarises to cghath before every push.

**Gotchas we hit:**
- Usage limits can kill agents mid-run. Branches and worktrees survive. Save uncommitted
  work as a WIP commit and rerun with a "continue in that worktree" note.
- A worktree-isolated agent can't run git in another agent's worktree. Finished work then
  lands on that agent's `worktree-...` branch, so merge from the reported commit.
- Never run two test runs with the same `CONTRACTOR_TEST_TAG` or `CONTRACTOR_PORT`.
- Kill hung headless Godot test processes left by stopped runs before the next full run.
- Bash heredocs mangle Python with backslashes and quotes, so write scripts to a file.
- CI runs the stock Linux Voxel Tools release editor. Verify a red CI suite on the custom
  Windows build too before blaming the engine (the spall check was a real bug).

## Wave 5: vehicles and supports (proposed 4 workstreams)

> **For cghath's agent, starting wave 5 while Captain's side finishes 4B part 3 (Captain, 2026-10-12):**
> - **New rule for both sides: debugging and logs. Read [debugging.md](debugging.md).** Every run
>   (tests, scripts, builds, playtests) keeps numbered logs (R/S/B/P + number, by date, PASS or
>   FAIL in the name) in one parent folder outside the repo that nothing deletes;
>   `tools/run_tests.sh` already does it for suites. Cite run numbers when reporting. Test-only
>   controls go behind `DevTools.on()` (debug builds or `--dev`), not `OS.is_debug_build()`.
>   The bug-report key, session logs and AI overlay are Captain's side's next: please don't
>   build them, but give wave 5's systems lines in them when they land.
> - **The base hub stays as it is for now.** `BaseHub` / `BaseLevel` (today's "FOB" base scene)
>   keeps working unchanged through 4B part 3. **Wave 5 turns it into the first friendly
>   FOB** (Captain: the players don't build a FOB; inland the squad deploys from a friendly
>   faction's FOB with the company's portable container modules; the LHD is the only base we
>   own; replacement troops fly in from the LHD at a cost). Design: "Bases: the LHD and
>   friendly FOBs" below. Don't rework the base hub before wave 5 picks it up, and coordinate
>   with Captain's side before changing `base_hub.gd`, `base_level.gd` or `base_economy.gd`.
> - **4B part 3 (the hot zone) is Captain's side's, in progress now.** Its files: new hot-zone
>   scripts, `ZoneDef` hot layouts (4,096 m square, 16 km², Captain), alert level, enemy
>   pressure, radio contracts (`Contracts.server_radio_contract`), `data/zones.json` hot
>   entries. Please leave those to Captain's side; QRF bases are on foot until wave 5's
>   vehicles, and the hooks for vehicle QRFs and helicopter/AAV insertion will be left for
>   wave 5 to fill.
> - **Since your last pull (on `dev`):** ragdolls for downed and dead bodies (`Ragdoll`, layer 6
>   "ragdolls"; a vehicle should collide with layer 6 and can call `Ragdoll.unfreeze()`), a
>   downed body never moves itself, first-person arms, plain-clothes civilians, intel fog on
>   briefings, clean test sessions, the item catalogue plan (vehicle parts, fuel and
>   launchers are wave 5 rows) and the bases design. See `CHANGELOG.md` [Unreleased].
> - **Running suites:** set `CONTRACTOR_PORT` (two runs, or a running game, on the default
>   24680 clash and look like hangs).

**Decided (design doc and handoff):**
- Aircraft are AI-flown only. Ground vehicles can be driven by players or AI.
- Vehicle armor is immune to small calibre: 7.62x54R and up penetrate or disable.
- Anti-armor works by round type: HEAT, tandem HEAT, HE/HEDP, thermobaric, top-attack.
- The four player-faction supports:
  - Blackhawk resupply: a grid reference, or green or yellow smoke.
  - Blackhawk transport (hot zones only): a grid or green or blue smoke. With neither, it
    loiters near the players, avoiding fire, until it sees one.
  - AAVs: from the LHD on the coast or the FOB inland, commandable.
  - Blackhawk extraction: a grid or purple smoke, landing near the spot if it's unsafe
    (terrain or obstacles; enemy fire doesn't move it).
- Supports are lost with their cargo and passengers.
- Weather and terrain decide what can fly or drive: storms ground helicopters, and AAVs
  can't work mountains.
- **Who fields the AH-1Z, MRAPs (MaxxPro, M-ATV), Bradley and Abrams (Captain, 2026-10-11):**
  America, and close allies only where they really operate those American exports. In the
  friendly set that is all four for the US; MRAPs for the UK (Mastiff and Ridgback, Cougar
  family) and Canada (Cougar, RG-31); no AH-1Z, Bradley or Abrams for either.

**Art:** Captain's `VehicleArt` from `noahgonzalez4506/Contractor-Assets-and-References`
(`scripts/vehicle_art.gd`, 13 vehicles at 5 cm). Copy it to `scripts/art/vehicle_art.gd`.
API: `instance(model, scheme)`, `prop(model, scheme)`, `size_m(model)`,
`spin_rotors(node, delta, rpm)`, `mesh(model, scheme)`. Models: `uh60`, `ah1z`, `aav7`,
`bradley`, `abrams`, `maxxpro`, `matv`, six technicals. Schemes: army, marine_gray, od,
desert, white, tan, red.

| # | Workstream | Owns | Checks |
|---|---|---|---|
| V1 | **Vehicle core.** A `Vehicle` body on Jolt with seats (driver, passengers, turret where the model has one), enter and exit through the Left Ctrl menu, cargo as a rolling stash (the inventory system, litres and mass), host-authoritative driving with client input, AI drivers following a path, damage: hit zones (engine, wheels or tracks, crew, cargo), hulls carving at 5 cm the way plates do, burning and wrecks saved with the zone | `scripts/vehicles/*`, the vehicle seats and entries in the interaction menu, wrecks in `GameState` | Drive, carry 4, load cargo, take damage; small arms bounce; 7.62x54R penetrates the light ones; a burning vehicle kills its passengers and its cargo; a client drives and a late joiner sees the seats |
| V2 | **Anti-armor.** AT4, RPG-7 (PG-7V, OG-7V), Javelin (top attack, lock-on), MAAWS, NLAW, SMAW as weapons with backblast, by round type against vehicles, structures (voxel blast by material) and infantry (frag, overpressure through the wound model) | weapon and round data in `items.json` and `rounds.json`, `scripts/combat/launchers*.gd` | Each round type against each target class; backblast hurts whoever is behind; Javelin hits the roof |
| V3 | **Helicopter supports.** An AI-flown UH-60 for resupply (lands, drops a pallet), transport (picks up and drops off the squad; hot zones only) and extraction (takes HVTs, loot and deposited items, and the people aboard). Calls by grid reference or smoke of the right colour; loiters until marked; landing-safety search; leaves under heavy fire or is shot down and lost; cost and cooldown through `Economy.server_pay_support`, drawn from the contract's support budget first | `scripts/supports/*`, the command menu's Support entry (0), 4A's `Extraction` (the helicopter becomes extraction's ride) | Each call by grid and by smoke; loiter then land on a seen smoke; an unsafe spot lands within 100 m; a lost helicopter loses its cargo and passengers; cost charged; a client calls one |
| V4 | **AAVs, LHD and FOB.** The LHD offshore on coastal zones, the FOB inland (4A's base hub is the FOB scene); AAVs deploying from them, commandable from the command menu (move, hold, follow, dismount), amphibious on coastal maps; motor pool at the base (4A placeholder) holding the company's vehicles between deployments | `scripts/supports/aav*.gd`, the base motor pool, zone coast or inland flag in `ZoneDef` | An AAV drives in from the LHD, takes orders, carries the squad, swims; the motor pool keeps a damaged vehicle's state |

**Order:** V1 first, or with a vehicle-body stub agreed up front, because V3 and V4 sit on it.
V2 can run beside V1.

## Wave 6: factions (blocked)

**Before this wave, Captain decides:**
1. The reputation tiers: what each tier unlocks.
2. The allied troop types.
3. What limits the allied-troop support menu.
4. How the real-world faction set (being drafted in the vehicle-model thread) replaces the
   repo's three placeholder factions.
5. ~~Who fields the AH-1Z, MRAPs, Bradley and Abrams.~~ Answered: the US and the close allies
   that operate them (see wave 5).

**Scope once decided (design doc):**
- **Persistent world.** Damage is repaired and positions reoccupied over campaign time.
  Factions run simulated operations between missions that move the front and post matching
  contracts.
- **Side locking.** Taking work from one faction locks you out of its enemies' contracts for a
  while.
- **Allies.** Reputation tiers unlock allied troops in the support menu. The USA, Great
  Britain and Canada sell gear and vehicles by reputation.
- **Enemies.**
  - Gear by region: Chinese, Russian, Iranian, insurgent.
  - Technicals and light vehicles, using Captain's technical models.
  - **Suicide bombers and VBIEDs** (Captain, 2026-10-11: "where it fits best in the roadmap").
    Insurgent behaviour, so it belongs here. A bomber on foot is a hostile carrying a placed
    charge that rides him (`Charges` already sticks to and rides people and moving bodies); his
    AI closes on the squad and sets it off, with tells (bulky clothes, ignoring shouts to stop).
    VBIEDs are technicals or civilian cars carrying charges, so they need wave 5 V1 (vehicle
    core) first. Counterplay: spot him, shout, shoot early, disable the vehicle.
  - Rival contractor teams.
  - Bounty hunters with a heat meter, and named, Nemesis-style hunter squads that remember the
    squad.

4A's `Economy` already keeps per-faction reputation as plain numbers, ready for tiers.

## Wave 7: art, world and weapons

**Art half (Captain's side).**
- Stormworks-style voxel characters at real scale on the same joints (in progress), then
  gear, weapons and environment from the asset pack.
- Every placeholder sits behind one function so it swaps in one place: `ZoneModule._build_proxy`
  (zone stand-ins), `PersonLook` (civilians and HVTs), the base hub buildings, `ItemIcons`.
- cghath's side doesn't touch `scripts/art/voxel_art.gd` or the soldier's look.

**Systems half (proposed 4 workstreams, any side):**

| # | Workstream | Notes |
|---|---|---|
| S1 | **Day and night, weather** | Time of day per zone, from the contract, and passing during a deployment (LRRP time acceleration later). Sun and moon light; darkness cuts AI spotting. Weather: rain, fog, overcast, storms, affecting sight, sound and AI detection. Storms ground helicopters (wave 5 supports read it). All saved with the zone and replicated |
| S2 | **NVGs and lights** | NVGs as helmet-mounted gear: flip up or down, green image with grain, a battery, a gen/FOV value proposed. IR lasers and illuminators visible only through NVGs. Weapon lights and visible lasers that the AI can see |
| S3 | **Weapon attachments** | Optics (red dot, magnified with a zoom), lights, lasers (visible and IR), suppressors (sound and AI hearing range, flash), grips (recoil, sway). Attachments live in the weapon's item state like its magazine, so they travel with it, save and replicate. Attach and detach in the inventory screen, using Captain's MOLLE-style attach points as the pattern |
| S4 | **Assists and controller** | Optional, off by default, host-set for co-op newcomers: aim slowdown, wound hints, objective markers, a simpler interaction menu. A full gamepad layout for every control, with radial menus on the sticks |
| S5 | **Voxel smoke (CS2-style)** | Captain, 2026-10-11: on the roadmap, "we'll tackle it when it's time". Smoke as a volume on a coarse voxel grid over the world: it spreads from the grenade cell by cell, flows through doors and windows, stops at walls and fills rooms, drifts with the wind and thins out. What a player sees and what blocks AI line of sight follow the real cloud (today: round puff clouds, `SmokeCloud.blocks` a sphere). Blasts push holes in it that refill; gunfire may part it briefly. Replicated as a seed and its events, so late joiners rebuild the same cloud. Coloured smokes keep their colour for the helicopter supports |

## Wave 8: player-built faction (design only)

One agent writes a proposal for Captain: what building your own faction involves, whether it
replaces or sits beside contracts, and the campaign-operation tier (multi-deployment
operations) the design doc puts under it.

## Item catalogue plan

Asked for by Captain (2026-10-11): "add loot items and misc as well to our roadmap". What the game buys, sells, finds and carries, and the wave each kind arrives in, so every item
has a place before it's built. **Everything here is Proposed** unless it names Captain or a
decision; prices are proposals against `data/prices.json` (sell back at `sell_ratio` 0.4) and
tune freely. "Loot" means found in zones; "contract zones" means loot capped at medium tier
(decided).

**Rules every new item follows (Proposed):**
- An item has a `type` in `items.json` and either its own price or its type's
  `default_by_type` in `prices.json`.
- **Buyable** is in the base shop's catalogue. **Sell-only** is in `not_for_sale` with a price
  (what it fetches). **Mission-only** is `not_for_sale` at price 0: it can't be bought or sold,
  only delivered.
- Loot tiers low, medium and high per item. Contract zones roll up to medium; hot zones and the
  rival PMC roll up to high.
- Loot goes in `ZoneModules.LOOT` (by module), the hostile loadouts (bodies) and cache crates.
- New items carry the tags AI scavenging reads (calibre, medical, grenade, armor), so the
  need-based rules (decided) pick them up without new code.
- Worn or damaged gear sells by condition, the way repairs already price it.

| Category | Have now | To add (examples) | Buy / sell | Price band | Where it drops | Wave |
|---|---|---|---|---|---|---|
| **Weapons** | M4A1, Mk18, M110, M17 | M249 LMG and an M320 underbarrel (the AR and grenadier stand-ins in `roles.json`), a breaching shotgun. Enemy guns by region: AKM, AK-74M, RPK, PKM, SVD, QBZ-95, Makarov. Allied: L85A3, C8 | Own guns buyable; allied guns buyable by reputation (decided); enemy guns loot, sell-only | 600-4500 (M17 650 to M110 4200); enemy guns sell for 200-600 | Enemy bodies (what they carry), outpost and HQ racks, caches | LMG and underbarrel: next (4B follow-up or backlog). Enemy and allied guns: 6 |
| **Launchers** | None | AT4, RPG-7 with PG-7V and OG-7V, Javelin, MAAWS, NLAW, SMAW (decided list) | AT4, MAAWS, NLAW, SMAW buyable; Javelin by reputation; RPG-7 and its rounds loot, sell-only | AT4 1800, NLAW 4000, rounds 200-600, Javelin missile 12000 (support-call scale) | Insurgent bodies and caches (RPG-7), QRF bases, armour crews | 5 (V2) |
| **Attachments, optics** | None | Red dot, magnified optic, light, visible and IR laser, suppressor, grip | Buyable, sellable; they stay on the weapon | 150-1500 (red dot 400, suppressor 900, magnified 1200) | Fitted to enemy weapons, mostly hot zone and rival PMC | 7 (S3) |
| **Ammo, magazines** | 5.56, 7.62x51, 9mm mags and loose rounds | 7.62x39, 5.45x39, 7.62x54R (it matters against vehicles), 40 mm, 12 ga, M249 belt boxes | Own calibres buyable; enemy calibres loot, sell-only | Loose 1-3 a round, mags 25-60, belt box 150 | Everywhere; bodies carry their weapon's calibre | 40 mm, belts: with the LMG and M320. Enemy calibres: 6 (7.62x54R with 5) |
| **Armor, carriers, packs** | Three carriers, three helmets, four plates, ten pouches, two packs | Chest rig (no armor, more pouches), 60 L ruck, enemy carriers and helmets (Russian, Chinese, insurgent rigs), allied armor by reputation | Buyable, sell by condition; enemy armor loot, sell-only | Existing 15-1600; heavy enemy armor sells for up to 600 | Bodies (AI takes armor only when calm, decided), outposts. No ceramic IV or heavy helmet in contract-zone loot | Chest rig, ruck: any time. Enemy and allied: 6 |
| **Medical** | 38 items (wave 3) | Nothing required | Buyable, sellable | Existing 8-2400 | IFAKs at compounds and villages; trauma kits, fluids at outposts and HQ medbays; blood and big IVs rare (decided rarity) | Done; loot spread any time |
| **Explosives, throwables** | Frag, five smokes, flashbang, breaching charge, zip cuffs | Demo block and det cord for sabotage (bridge, fuel depot, vehicle park), thermite, claymore, 40 mm HE and smoke, chem lights. Enemy IEDs: disarm or destroy, never sold | Buyable, sellable; IEDs mission-only | 40-600 (demo block 500, thermite 250) | Zip cuffs as loot at checkpoints, outposts and hostile bodies (Captain, backlog item above); grenades on bodies and in caches | Demo and thermite with the sabotage mission type; IEDs and bombers: 6 |
| **Comms, nav, sight** | Radio, binoculars, ear protection | Field radio (the contract board in the field, Captain), enemy radio (hear zone chatter, decided), GPS, compass, rangefinder, IR strobe, NVGs by generation, recon quadcopter and FPV drone (decided), jammer (heavy, decided) | Own gear buyable; enemy radio loot-only (zone-bound, goes quiet when they switch) | GPS 400, NVG 3000-9000 by generation, quadcopter 2500, FPV 800 each, jammer 6000 | Enemy radios on squad leaders and at comms sites; NVGs on hot-zone and rival PMC bodies | Field radio: 4B. Enemy radio: hot zone (4B part 3). NVGs, IR: 7 (S2). Drones, jammer: 6 with enemy drones |
| **Food, water** | None | MRE, water bottle, canteen, hydration bladder | Buyable, sellable, cheap | 5-20 | Villages, outposts, packs on bodies | **Deferred** (Captain: food and water simulation not a priority). Weight and trade value only until LRRP fatigue wants them |
| **Intel** | Laptop 3000, phone 1200, documents 800 | Hard drive, USB stick, marked map, SIM card, officer ID, LRRP camera photos (count once carried out, decided) | Never in the shop; banks as leads, or sells to other factions at `intel_sale_price` with the risk (decided) | Existing; drive 1500, map 600 | Squad leaders, officers, outposts, checkpoints, intel objectives (decided) | Now (4B); camera with LRRP |
| **Salvage, valuables** | Electronics salvage 450 | Weapon parts, copper wire, batteries, a generator, medical salvage, cash bundles (bank at face value), gold, watches | Sell-only; salvage share claims what's left in the field (decided) | 50-2000 | Compounds, HQ safes, wrecks, rival PMC bodies (higher tier). Taking from civilian homes costs local reputation | Now (4B); more kinds any time |
| **Contraband** | None | Smuggled cigarettes and alcohol, captagon, antiquities, counterfeit dollars, unregistered weapons | Not in the shop. Shady fixers (like `salvage_union`'s) pay well; lawful factions lose reputation. Or hand it to the client for a small bonus | 300-5000 | Smuggler compounds, checkpoints, caches; the rival PMC's stashes (ties to the conspiracy plot) | 6 (needs reputation and fixer markets) |
| **Vehicle parts, fuel** | None | Jerrycan, spare wheel, track links, repair kit, vehicle battery, engine parts, .50 BMG belts, vehicle shells | Buyable at the motor pool; parts sell; wreck parts loot | 50-1500 (.50 belt 200) | Wrecks, technicals, QRF motor pools, fuel depots | 5 (V1, V4) |
| **Module and fortification materials** | None | Shipping containers, steel sheet, electronics, generators and fuel bladders (company modules, built and upgraded on the LHD); sandbags, HESCO, concertina wire, camo net (fortifying your space at a friendly FOB, FOB defence) | Bought in bulk at the LHD; salvaged from destroyed outposts; carried as crates in vehicles | 50-2000 a crate | Destroyed outposts and HQs, supply convoys | 5 (needs cargo). Captain (2026-10-11): upgrades cost cash and materials; no player-built FOB, see "Bases" below. Full base construction only with wave 8 |
| **Keys, access** | None | Door and padlock keys, HQ keycard, safe combination (a document), technical's keys | Mission-only, zone-bound; a quiet alternative to breaching | 0 | Officers, guards, HVTs | Hot zone HQs (4B part 3) or 6 |
| **Quest, story** | HVT case, supply crate | Rival PMC evidence (ledgers, contracts, a drive), crash-site flight recorder, MIA squadmate's belongings | Mission-only | 0 | Set by the contract | 6 onward (story contracts) |
| **Personal, civilian** | None | Dog tags, wallets, photos, prayer beads, civilian phones (not intel), civilian clothes (gear-based disguise is later scope) | Sell-only, `misc` default 50 or less | 5-50 | Bodies, villages. Taken from civilians: local reputation hit | Any time as `misc`. **A fallen squadmate's dog tags count (Captain, 2026-10-11):** taken off the body and brought home they close the case (KIA, not MIA: no recovery contract), pay the family's death benefit, put the name on the base's memorial wall and lift the company's standing with recruits a little; tags left behind count against it (the effects are Proposed) |

**Order, in short:** 4B uses what exists (intel, salvage, zip cuffs as loot, the field radio).
The next small pass adds the LMG, M320, 40 mm and belts so every role has its real weapon.
Wave 5 brings launchers, 7.62x54R, vehicle parts and fuel. Wave 6 brings enemy and allied gear
by region, contraband, drones and the jammer, IEDs, keys and story items. Wave 7 brings
attachments and NVGs. Module and fortification materials follow wave 5; full base construction
waits for wave 8.

## Bases: the LHD and friendly FOBs

Captain (2026-10-11): the players don't build a FOB. The **LHD is the company's only base**, and
inland the squad deploys from a **friendly faction's FOB** in the area, bringing the company's
own **portable modules**. **Replacement troops are flown in from the LHD at a cost** (no hiring
at a FOB). The rest of this section is Proposed.

**The LHD (owned):** safe (never attacked), fully stocked, does everything: the armory, the
full medbay (serious injuries recover here), the hiring board, aircraft maintenance, the
memorial wall. It moves between regions with the company (days of travel). Every company
upgrade lives here and is paid in cash plus materials.

**Company modules (owned, portable):** shipping-container modules, built and upgraded on the
LHD, set up at whichever friendly FOB the squad works from. Upgrade one once; it works at every
FOB.
- Armory container: the squad's gear and resupply forward.
- Med container: field surgery: stabilise, and back in the fight sooner (serious cases still go
  to the LHD).
- Comms container: radio chatter, the intel cell, drone control.
- Workshop and drone container: repairs, quadcopters and FPVs.
- Generator and fuel bladder: power for the rest (the host rations theirs).
Moving regions means flying or driving the modules over: days and a lift.

**The friendly FOB (the host's):** the same downsides as a FOB of our own, in their terms:
- Supply: the host's allocation, plus their quartermaster at their prices (reputation-gated).
  Our own stock comes in from the LHD by helicopter or convoy, and what's there is all there is.
- Footprint: the host gives us space, a tent, then a bay, then a hangar slot, growing with our
  reputation with them. It caps how many modules we can set up.
- Power: rationed; heavy modules need our own generator and fuel.
- Threat: the enemy attacks FOBs (by heat and alert level): FOB defence contracts. Overrun, what
  we staged there is at risk.
- Caps: no hiring, no heavy aircraft maintenance, field care only.
- One per region, set by who holds it: a region with no friendly faction means the LHD only, or a
  shady fixer's compound at a price and a risk.
- New: access depends on the host. Low reputation, breaking their rules (contraband, abusing
  prisoners) or working for their enemies can get the company thrown out.
**Reputation perks from the host:** more space, priority on their helicopters or QRF, their
surgical team, a fuel allocation, quartermaster discounts.

**Replacement troops (Captain):** hired on the LHD and flown in to the FOB (or the zone) at a
cost: the hire plus the flight, more for a hot LZ, and it takes time (the next lift). Bodies and
casualties go back the same way.

**Armory and storage (Captain, 2026-10-12): a refactor of today's floor stash.** Today
(`BaseArmory`) every item lies loose on the armory floor and spills into the yard. Instead:
- **Physical and organised:** every kind of item has its own place that makes sense: weapons
  on racks, plates, carriers and helmets on shelves, ammunition by calibre, grenades and
  explosives in their own crates, medical on its own shelves, pouches and small kit in
  lockers. A few visible props per area, not every item lying out.
- **Plus an ACE3-style Virtual Arsenal:** a menu on the storage that lists everything there and
  kits you out from it (and takes gear back), drawing only on what the company really owns.
- **Capacity is physical:** when the armory is full, buy storage containers to extend it, or
  upgrade it.
- **At friendly FOBs:** the VA works on the storage the host assigns us. At low reputation that
  storage is **pallets with hard boxes**, like a CIF issue point, for plate carriers, helmets and
  other kit, while weapons, ammunition and grenades go in their **own mini armory**: lockable
  crates like Halo's armory crates. Better storage comes with reputation and our own armory
  container module.
Timing (Proposed): designed now; built as a wave 5 workstream with the FOB and the container
modules (the base hub becomes the first friendly FOB then), so it isn't built twice. Captain's
side can take it after 4B part 3, coordinated with cghath since the base files are shared.

**Materials:** containers, steel, electronics and generators build and upgrade modules (on the
LHD); sandbags, HESCO, wire and camo nets fortify our space and help in FOB defence. Waves:
modules and FOB deployment with wave 5 (they need lift and cargo; the 4A base hub becomes the
first friendly FOB), FOB defence contracts with wave 6 (factions), full base construction with
wave 8 (the player-built faction).

## Backlog (small, any time)

**From Captain's playtests and the reviews:**
- **Zip cuffs lootable in zones** (Captain, 2026-10-11). They stay a base-shop buy, but some
  should also turn up as loot in zones (checkpoints, outposts, on hostile soldiers' bodies), so
  a squad that forgot them can still find a pair. See `ZoneModules.LOOT` and the hostile loadouts.
- **Settled ragdolls react** (Captain, 2026-10-11: "when it's a good time"). A frozen body or pile
  wakes and moves again for a blast (Throwables, charges), a body landing on it, a vehicle and
  being walked on hard; then settles and freezes again. Hook: `Ragdoll.unfreeze()` exists.
- **Conscious but can't stand** (Captain, 2026-10-11: on the roadmap). A new medical state between up
  and down (down is always unconscious, Vitals): both legs broken or destroyed, a shattered
  pelvis or a spinal hit leave a soldier awake but unable to stand. Prone only, crawling
  (CRAWL_SPEED), a pistol and self-treatment still possible, no carrying. AI casualties in it
  call out and crawl to cover; medics treat them like any casualty; a splint or surgery can get
  them up again (Proposed). Today a downed body never moves itself.
- You can fire during a pickup or equip animation.
- A dragged casualty eases back about 1 m when put down.
- An equip animation plays even when the action then fails.
- M opens the map over the inventory screen; Tab does nothing while the map is open.
- The inventory screen's Use only matches a task's first-choice item.
- AI squadmates don't load magazines from loose rounds, and role kits carry no loose rounds.
- The voxel edit log is never compacted.
- Every inventory change re-sends the whole inventory snapshot. That's fine on a LAN but needs
  a lighter path before internet play.

**Handoff checklist items still open:**
- Make permadeath on bleed-out apply to AI squadmates only, and MIA when they're left behind
  alive. 4A's base does MIA; check that the rule reads right everywhere.
- Update `docs/squad_design.md` for buddy pairing and the Throw, Carry, Drag and treatment
  intents. They're already in the code.
- AI voice callouts. The audio hook exists: `res://audio/callouts/<id>.ogg`.
- Check that X, Z and C don't clash with any older bindings.

**Docs to export from claude.ai into `docs/`:**
- ~~The mission brainstorm doc~~: in [mission_brainstorm.md](mission_brainstorm.md) since 2026-10-11.
- The Arma mod research doc.

**cghath's dropped wave 3 extras**, for Captain's side to take or leave. They're on cghath's
local branch `local/wave3-cghath` and never pushed:
- CPR slows the 10-minute arrest window fourfold and holds oxygen up.
- Blood pressure; a slow heart pumps less and a racing heart bleeds more.
- IV lines pull out when carried, dragged or sprinting, and can be removed by hand.
- IO in the humerus and tibia, never into a broken bone.
- Wall-adjacent blast doubling, and flashbang facing.
- A breathing-sound hook.
- About 380 more medical test checks.

**Noted in the comparison against the design doc:**
- Falls can kill from 6 m; the doc says about 10 m.
- Hypothermia counts standing still.
- AI non-medics may use the needle, IVs and epinephrine.
- A heart-rate comment says 150/45, while the code uses 200/35.
- The epinephrine roll cancels a running concussion knockout.

## Open questions for Captain (all in one place)

1. A voided contract (8 civilian casualties): does it claw back the 30% advance? Today it does.
2. A hot zone with several contracts: is the 8-casualty void per contract or per deployment?
   Today it's per deployment.
3. Hot zone size: 8-16 km² (twice the area) or 16-32 km² (twice the width)?
4. Where can the contract board be reached: only at the FOB, or also from the main menu?
5. ~~Who fields the AH-1Z, MRAPs, Bradley and Abrams?~~ The US, and close allies that operate
   those exports (Captain, 2026-10-11).
6. The wave 6 decisions above: the support-menu limit and the faction set. (Reputation tiers,
   ripple, decay and allied troops are decided in [mission_brainstorm.md](mission_brainstorm.md).)
7. Should players start in their role kit? `CompoundLevel.player_role_kits` is off; 4A's
   roster kits AI squadmates out.
8. The M855 rule: does it count as level III beyond about 200 m?
9. Is the fragment serious-wound rate right? This is from wave 1's tuning.

## References

- Repo: `cghath/Contractor`, branch `dev`; CI on GitHub Actions runs every suite on push.
- Engine: Godot 4.7.2 with Zylann's Voxel Tools 1.7. On Windows, the custom editor is at
  `%USERPROFILE%\Downloads\GodotVoxel_1.7\godot.windows.editor.x86_64.exe`.
- Tests: `GODOT=... tools/run_tests.sh [suites]` (20 suites).
- Builds: `tools/make_build.sh <label> "<notes>"`, which writes `builds/<date>_<label>/` with
  `play.bat` and `BUILD.txt`.
- Design: `docs/contractor_design_doc.md`. Decisions and agreements:
  `docs/contractor_handoff.md`. Waves: `docs/build_plan.md`. Wave 4B: `docs/wave4b_handoff.md`.
