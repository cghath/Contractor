# Changelog

All notable changes to Contractor are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Add new entries under
**Unreleased** in the same commit as the change. The README's "Versioning and changelog"
section explains how to cut a release.

Entry types: **Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**.

## [Unreleased]

### Squad AI: stacking outside, clearing on you, longer order range, doctrines that act (Captain, 2026-10-20)

#### Fixed
- On a clear order, the stack forms outside the door. Before, a stack spot could be placed
  through the wall, inside the building, by a corner or an uneven wall. Each spot is now checked:
  outside the building, on the door's outer side, and not pulled through a wall. If not, it's
  moved further out or to the door's other side.

#### Added
- **Clear on me** (Command > Move > Clear > 7, or say "clear on me"): they stack outside the
  door, call "Stacked up. On you.", and hold until you go in. Then they follow you in, one after
  another. If you go down, they go in on their own.
- **Following you into a building**: walk into a building while your squad follows you (not in
  Safe mode, not at the base) and they stack on its door and clear it on their own. If they know
  of an enemy inside, they flashbang it first (a frag if no one has a flashbang), but never with a
  civilian or HVT seen inside. Walk away and they drop it and follow you again.
- Voice orders: "clear that building", "breach and clear", "clear on me".

#### Changed
- Orders reach 800 m: the crosshair finds a point or a target that far out (was 150 m for a point
  and 300 m for a target).
- Doctrines now shape how each side fights (AI bar G-15). Every number in the doctrine file acts,
  each as a lean against its side's usual doctrine:
  - the usual enemy (insurgents) and your squad (the PMC) fight exactly as tuned;
  - a regular army on the hostile side (the Eastern Concord's) reacts quicker, aims tighter,
    frags more often, pushes a bound sooner and hooks wider, and holds together longer;
  - the rival PMC among the hostiles is sharper again.
- AI bar G-04 marked done: the base of fire already checks its line before firing, standing over
  its cover or moving to a fire spot.
### Feel round 2 (Captain, 2026-10-20: his Star Citizen on-foot reference; Contractor learns from it)

#### Added
- **Pace on the mouse wheel.** On foot and not aiming, the wheel steps through four paces: a
  slow walk, a walk, a brisk walk and the jog (the default). Sprint stays on Shift. The HUD
  shows the new pace briefly. P still toggles quickly between the jog and the last slower pace.
  The command menu, the interaction menu, a grenade in hand and aiming still keep the wheel,
  and a free-spinning wheel moves one pace at a time.
- **Breath cycle with pauses.** A breath now goes in, holds at the top, goes out and holds
  longer at the bottom. The breath doesn't move the sight during either pause, so a patient
  shot can be timed into one. A breath takes 6 s with fresh legs and 2.5 s winded.
- **Carry states.** Sprinting, vaulting and mantling force the weapon low. Mantling now reaches
  other players too, so they see the weapon go low, and you can't aim mid-climb. Bringing the
  weapon up from low (the sprint carry or the low ready) takes up to x1.35 its usual ADS time.
  After a sprint the aim sways up to x2.5 for a moment (it builds over 1.5 s of sprinting and
  fades over 1.2 s).
- **Steadier head.** As the steps move the view, it turns slightly the other way to keep
  looking at a point 10 m ahead, so the world in front stays put while the body moves (only
  with head bob on).

#### Changed
- **Holding your breath scales with fitness.** Fresh, it lasts 10 s and the gasp after is 3 s.
  Spent, it lasts 1 s and the gasp is 6 s (it was 6 s / 3 s with a flat 2 s gasp). The gasp's
  extra sway eases off over its second half.
- **Third-person reloads match first person.** The weapon now moves on each reload's own keys
  (tipped and brought in for the magazine, the look and the seat, the bolt work), about 25%
  bigger so it reads at a distance. Near the view, the action locks back and slams home and a
  belt-fed's feed cover opens and shuts, as in first person. The parts are warmed with the
  uniform, so the first reload doesn't hitch. Far bodies (animation LOD) keep the cheaper
  magazine-only split. The phases already reach every peer and AI through the host's
  `_reload_began`; tests now check them over ENet and on an AI body.
### Story act 1 and the manhunt's markers (Captain, 2026-10-20: "the intel case doesn't tell you where dude is", "both markers show on the first map but not the second map")

#### Fixed
- **A manhunt's intel says where the man went.** Picking up the intel (the laptop, the papers or the
  compound's hard case) now gives his zone, his site and its grid reference. The radio says it, and
  his objective names the site.
- **Each zone's map shows only its own objectives.** The map used to show the briefing's list for
  the whole deployment: the man next door sat at the first zone's centre, and after the crossing
  the second map showed nothing. Now the map shows the deployment's live objectives that play in
  the zone you're in. The supply line and the convoy chase had the same problem and are fixed too.

#### Added
- **The story (docs/story.md).** The main arc is in four acts: the Vantage Group's conspiracy,
  uncovered through intel. Act 1, "The coast", is built: four story contracts for Meridian against
  Black Ridge, then Vantage.
  - **Paper trail**, an intel grab.
  - **The quartermaster**, a two-zone manhunt.
  - **The crates**, a two-zone supply line.
  - **Vantage point**, a raid for a Vantage team's ledger.
  - Each one unlocks once the one before it is done and its clue is found (Captain: "both").
  - The client's liaison calls each one in on the radio.
- **Clues and evidence.** Each story contract's intel adds a clue and evidence, and the evidence
  count opens each later act. Ordinary intel turned in counts too: 4 pieces make 1 evidence, and
  each Vantage ledger is 1, up to 3.
- **Leads on the contract board.** It shows the act, the evidence, what the next story contract
  waits for, and every clue so far.
- **Later acts and three faction arcs are data stubs**, waiting to be written.
### Economy overhaul (Captain, 2026-10-16: "too easy overall but mission expenses swing it negative fast")

Built from docs/economy_proposal_2026-10-20.md. Income is steadier and lower, the costs that
spiralled are capped, and the debrief and the base say where the money went. Details and the
measured before/after: docs/economy.md and the proposal's "Built" section.

#### Changed
- **Contract pay about a third lower** at every rating. Hot zones keep their better rate (x1.4).
  The no-civilian-casualties bonus is 5% (was 10%).
- **Hot zones start small.** The squad goes in on the one or two contracts it took for the zone
  (Captain: "with radios and villages entering hotzones with one or two objs will be good"). The
  zone no longer tops them up to 3-6 on arrival. More come in over the radio as the squad works,
  and from the villages: asking a villager in the hot zone you're deployed to hands you the
  locals' job live (once a zone a day), instead of putting it on the base board. Contracts taken
  on the spot pay nothing up front, all on completion.
- **Intel sells for what it's worth:** its own value, $500 to $4,000 (the HVT case $3,000), not
  a flat $6,000 a piece.
- **Wages and upkeep are paid every day,** a seventh of the week's bill. Each debrief shows its
  own days, and no debrief takes a whole week's bill at once. Loan installments stay weekly.
- **Capped shocks.** A helicopter lost on a support call costs a $15,000 deductible (was
  $30,000-40,000). Each bought respawn costs a quarter more than the last, never over $8,000 (was
  half more, no cap). The death benefit is $10,000 (was $15,000).

#### Added
- **Where the money came from:** a new debrief section lists advances, completion pay, bonuses,
  fines, clawbacks and what was sold in the debrief. Wages and upkeep show their days. The net is
  labelled "before loot", and a "Sold here" figure is added.
- **Books tab** on the base screen: running costs a day, loans and the next installment, the last
  7 days of money by kind, and the 20 newest payments. The base header and the contract board
  show costs a day instead of "weekly bill in N days".

#### Fixed
- **Intel could be sold twice.** Intel brought out goes to the debrief, never to the stash. The
  shop doesn't buy intel. A piece already debriefed is worth nothing if it is carried out again.
- **Hire-and-release for free kit.** Someone let go takes the kit they were issued. If it's
  missing, it comes out of the stash or its sell value is charged.
- **Radioing for contract after contract** no longer pays 30% of each up front.

### Footsteps (Captain, 2026-10-20: "the current ones are terribleee", then "too much like minecraft, too heavy, need running, walking, slow walking, crouching sounds")

#### Changed
- **A sound per pace.** Footsteps now have their own sound for each pace: sprinting, jogging,
  walking, a slow walk and crouching. Each comes in a soft-ground version (dirt, grass) and a
  hard-floor version (concrete, wood, metal), so 10 sounds with 8 variations each.
- **Lighter.** No deep thud any more:
  - a light heel tick and a heel-to-toe roll;
  - the ground's fine grit, or a crisp tap on hard floors;
  - a scuff, which becomes a skid at a sprint, plus a little kit jingle when sprinting;
  - crouching is a muffled shuffle with cloth rustle.
  Each step slower is quieter.
- **New generator layers.** The sound generator has new layers (thumps, grains, rustle) and a
  per-sound variation count, so other sounds can use them too.
### Weapon detail pass (Captain, 2026-10-20: "we need to do a weapon detail pass soon")

The parts the reloads work are now on the models, they move in first person, and each reload
beat has its own sound.

#### Added
- **Model details, per weapon:**
  - M4, M27, HK416, C8: ejection port with the bolt carrier in it and the dust cover swung open
    below it. Also the brass deflector, forward assist, T charging handle, bolt catch paddle,
    magazine release and safety.
  - AK family (AKM, AK-74, RPK, SVD): ejection port, carrier and charging handle, the long
    safety lever, magazine release paddle and dust cover latch button.
  - L85A2: the cocking handle now rides in a cut slot, and the bolt carrier shows in the
    ejection port. Before, the port was too thin to show.
  - PKM, M240B, M249: a feed cover hinged at its front, with its latch (and its rail on the
    M240 and M249). A feed tray under the cover, a brass belt with links from the box onto the
    tray, and a charging handle on the right.
  - Mosin: the bolt handle and ball knob now sit above the stock line (the old ones were half
    inside the wood).
  - Springfield: the bolt in an ejection port, its shroud, handle and tactical knob.
  - M17 pistol: slide serrations and a slide stop lever.
- **Moving parts in first person**, split from the weapon and tagged like the magazine:
  - AR family: the carrier is locked back on an empty reload and slams home when the catch is
    slapped.
  - L85: the handle and carrier run forward when the release is pressed.
  - AK: the carrier and handle rack back and spring home.
  - Belt-feds: the handle is charged on an empty reload. The cover flips up while the box is
    changed and slams down at the end. The belt comes off with the box.
  - Bolt-actions: the handle turns up, the bolt draws back, then goes forward and down.
  - Pistol: the slide is locked back on empty and goes home.
- **A sound for each reload beat**, all generated (data/sounds.json `reload_*`): magazine out,
  magazine in, bolt back, bolt forward, cover open, cover close, belt laid, clip stripped. They
  replace the single "reload" sound that played at the start.
- **Third person follows the same keys.** When a reload begins, the host tells every peer the
  weapon, whether it's empty and how long it takes. Each peer then times it on its own clock:
  - the support hand goes from part to part and to the pouch;
  - the held weapon is drawn without its magazine while the magazines move: out, carried,
    dropped and in;
  - the beat sounds play there too. A player's own reload starts at the key press, not after a
    round trip to the host.

- **The pistol's magazine is its own part** (Captain: "pistola needs a sep mag too"). It sits
  in a well up the grip and drops out the bottom on a reload; a new one goes up in its place.
  Its floorplate is the grip's bottom.

#### Changed
- **The PKM rebuilt to the real gun** (Captain: "realistic pk please"). The old one had the
  box on the left, a wooden handguard and a perforated barrel jacket. Now:
  - the 100-round box hangs under the receiver's right side, and the belt feeds in from the
    right;
  - the ejection port and its flap are on the left;
  - a bare fluted barrel with a slotted flash hider;
  - the gas cylinder under the barrel, with the bipod on the gas block, legs folded back;
  - the carry handle folded down along the barrel.
- **Full-length magazines.** Real magazines didn't fit the 26 cm weapon frame, so every rifle
  but the WG-50 now has 6 cm more frame below (`RIFLE_BELOW`). Every point read off a rifle
  follows the change, so the weapon sits in the hands and at the eye as before.
  - AR family: the 30-round magazine is 18.5 cm overall, 12.5 cm below a 6 cm-deep well. The
    pistol grip is 10 cm, like an A2's.
  - AK: the banana hangs 17 cm under the receiver.
  - L85: 11 cm under the housing, at its real depth front to back.
  - M240 and M249 boxes are real size, and the M249 box's bottom now comes off with it.
  - Each magazine goes up into a real well, so the well shows open while it's out.
- **HK416:** the piston rod no longer rides on top of the rail; the real one is hidden. It now
  has a chunky free-floated quad rail over the gas block and a deep E2-style stock with its
  storage tubes.
- **Optics on the M240 and M249** ride the feed cover's rail and lift with it, as on the real
  guns.
- **C8 proportions:** it now has its real 15.7 in heavy barrel (longer than the M4's) ahead of
  a carbine-length handguard and an M4-length upper. Before, the upper ran 37 cm, half as long
  again as a real one.
- **reload_points** now gives each hand target on its new part: the AR's T-handle and catch
  paddle, the AK's knob, the belt-feds' right-side handles (the M249's was on the left) and the
  covers. They also account for a suppressor's length.

### Reloads reworked, and the L85's (Captain, 2026-10-20: "reload anims also need work")

References he named: Sicario's AR reloads, AK and AR reloads, common media (Heat, Modern Warfare
2019, Tarkov), and "make sure our L85 has a good reload and look too".

#### Changed
- **The magazine comes out.** It's now its own part in first person: the hand strips it out and
  stows it (tactical), or it falls free (empty). A fresh one comes up from the pouch.
- **Shared by every reload:** the weapon tips in so you glance at the well as the new magazine
  goes in, which is seated with a bump and given a tug. The weapon comes back up with a small
  overshoot.
- **Per family, in first person:**
  - AR: an empty reload ends with a slap on the bolt catch.
  - AK: the magazine rocks out and rocks in. An empty reload strips the old magazine with the
    new one, then racks the handle from underneath.
  - L85: it comes out of the shoulder and the hand reaches back under to the magazine behind
    the grip. An empty reload presses the bolt release, then taps the cocking handle forward.
  - Belt-feds: the gun is charged when empty, the cover opened, the box swapped, the belt laid
    and the cover slammed shut.
  - Bolt-actions and pistols also have their own reloads.
- **Empty reloads take longer**, because the bolt is worked: AR +0.3 s, AK and L85 +0.5 s,
  belt-fed +0.5 s, pistol +0.2 s. A weapon can set its own "reload_empty_s". AI squadmates take
  the same time.
- **Third person:** the support hand now works the weapon's real magazine, behind the grip on
  the L85.
- **The L85A2 model:** a magazine housing lip, the magazine release, the bolt release plunger,
  the right-side cocking handle and its slot, an ejection port and the cross-bolt safety. The
  handguard now runs back under the support hand, which now holds the handguard.

### Movement feel pass (Captain, 2026-10-20: floaty/slidey, camera, speeds, clunky actions; Star Citizen as the target)

#### Changed
- Paces for a man in kit: jog 3.6 m/s (was 4.0), sprint 6.0 (6.5), crouched 1.7 (2.0), prone
  0.7 (0.8), aimed half pace (was x0.6). Starts take 0.4 s to a jog and stops 0.28 s (were 0.3
  and 0.2), so moving has some weight without sliding.
- Jumps are a 0.6 m hop (were 0.9 m) with much less steering in the air.
- Going prone takes 0.7 s and getting up 0.9 s for players, slowed meanwhile. The view eases
  between stances instead of moving at a flat rate, and leaning rolls the view less.
- The view has weight: a dip on each footfall, a dip on landing that grows with the fall, a
  small nod when you set off or stop, a slightly wider view at a sprint, and the weapon trails
  your mouse a little (much less aimed). Turning head bob off in Settings turns these off too.

#### Added
- Walk: P toggles a walk (half pace) and back to the jog. Sprint still sprints. Rebindable.
### Loot rotation and a real rarity spread (Captain, 2026-10-20)

#### Added
- 72 new items, all priced, described and given a use: 13 guns (M16A4, Colt Canada C7A2, AKS-74U,
  AK-74M, RPK-74, Type 56, Zastava M70, AK-103, PKP Pecheneg, SVD-S, Glock 17, SIG P226, M1911A1)
  with .45 ACP magazines and rounds; 8 optics (Aimpoint T-2 and CompM4, EOTech EXPS3, ACOG TA31,
  Elcan Specter DR, Razor HD 1-10x, Leupold Mark 5HD, Schmidt & Bender PM II); 5 attachments
  (angled foregrip, M600 light, PEQ-15, 5.56 and 7.62 suppressors); carriers (Crye JPC and AVS),
  helmets (PASGT, MICH, FAST), plates (AR500 steel, PE medium, ESAPI), 3 packs and 3 pouches;
  5 grenades (RGD-5, F-1, M67, RDG-2 smoke, multi-bang); valuables (cash roll, euros, cash brick,
  watch, gold coins, rough gems, silver) and contraband (hashish, heroin, tramadol); 11 intel
  items (sat phone, SIM bag, hard drive, marked map, codebook, frequency list, tablet, drone
  controller, SD card, passports, written orders); 4 salvage items (copper wire, filters, solar
  panel, truck tyre).
- Item rarity: every item has `stats.rarity` (common, uncommon, rare, very_rare), the commonest
  tier it turns up in, ready for the tooltip to colour.

#### Changed
- Loot rotation: the Western rifles and pistols, nearly every optic and attachment, carriers,
  plates, helmets, packs, pouches, night vision gen 2 and 3, coloured smokes, breaching charges,
  knives and 19 medical items that never appeared anywhere now turn up in the tables. An HQ's
  weapons cache has its own table (Western rifles, optics, night vision, most of the very rare
  prizes); barracks hold personal kit; medical chests carry the full range of drugs, fluids and
  surgery kits.
- Rarity: every table's tiers are deeper (common boxes hold 2-3 things or a bundle, very rare
  holds real prizes: cash bricks, gems, gold, a sat phone with a codebook, a suppressed HK416).
  Cash and cheap intel are common, the $1,400 cash bundle is uncommon, jewellery and contraband
  rare. Very rare weights rise a little at hot-zone sites (HQ 4 to 5, QRF 3 to 4, compound 2.5 to 3.5).
- Dead drops, hidden caches and the HQ strongbox roll a rarity tier too (pools in
  loot_tables.json), instead of picking from fixed lists. A strongbox's valuables now vary from
  a modest stack to a real prize; it still always holds one contraband and one intel item.

#### Fixed
- The shop sold cash bundles, gold bars, jewellery and relics (they were missing from
  not_for_sale); valuables and contraband are found, never bought.
### The theatre map and the map screens in the shared look (Captain, 2026-10-20)

#### Added
- A theatre (world) map. Open it with World or Tab on the map (M), or with Theatre map over the
  ops desk's region map. Every zone is drawn as its own shaped area: neighbours share a border,
  region borders are drawn heavier, and the sea and the LHD lie to the west. Each zone is filled
  in the colour of whoever controls it: the company blue, allies green, Black Ridge militia
  orange, hostile armies red, neutral grey, and hatched when contested. Badges mark hot zones,
  contracts held and offered, a skirmish going on now, the enemy's alert while you're there,
  fights there this week, and flashpoints. The squad's zone is ringed, home (the FOB, or the
  LHD) is marked, links show their crossings, and each region's name gives its travel days from
  home. Hover a zone for who holds it, the threat, the contracts, recent fights and the rebel
  support tier there; the side panel shows the same for the picked zone, plus the legend.
  Pan and zoom with the mouse, keys (arrows move between zones, WASD pans, + and - zoom, F fits)
  or pad (d-pad and left stick, right stick pans, shoulders zoom).
- Zone control (`scripts/campaign/zone_control.gd`): who holds each zone, read-only for now.
  The base is the company's, a hot zone its faction-war holder's, any other zone the target of
  a contract there, else Black Ridge. A "zone_control" campaign section (synced to clients)
  overrides it and holds the home, for the zone-flip work to write.
- Closed contracts remember their zone, so the map can show where the fights were.

#### Changed
- The map screen (M) is in the shared look. Its bar wraps onto a second line in a small
  window, and a "?" button opens its controls (now including Tab for the theatre map).
- The briefing and extraction panels on the map use the shared text styles: 16 px body, 14 px
  notes and section heads, nothing smaller and nothing faded. Map labels and the ops desk's
  region map are 14 px or more, and the region map shows each zone's controller colour.
- The UI fit checks cover the zone map, the theatre map, and the briefing and extraction panels
  at all 10 window sizes and 4 UI scales.
### The LHD is home until you take a zone for the FOB (Captain, 2026-10-20)

Design: docs/lhd_home.md (the Captain's calls, and the Proposed ones for him to confirm).

#### Added
- A new campaign starts aboard the LHD, a ship you can walk around. The hangar deck holds the
  armory with the stash on its floor, the shop and supply cage, the muster line, and the vehicle
  park with the motor pool's vehicles parked in it. The medbay and the hiring office are their own
  compartments. Two stairways lead up to the flight deck, where helicopters stand on their spots
  and the ops room is in the island: deploy from there. Squadmates have a navmesh on both decks
  and the stairs. Clients join aboard like at the FOB.
- Taking a zone. A zone flips to the company once every HQ and QRF base in it has been taken out,
  counted across deployments (today, the hot zones). While home is the LHD, the client's liaison
  calls: the LHD's charter is running out and the client wants the company ashore. A
  seize-and-hold contract for that zone goes on the board: take the zone's HQ, then hold it
  through the counterattack. Lose it or let it lapse and it comes back the next day.
- Winning it makes that zone the FOB: home moves ashore to the base zone, built on that zone's
  ground. The stash, roster and motor pool move with the company, and the base takes that zone's
  place on the region map. The LHD stays offshore as the coast's support origin.
- A new test suite, lhd_home.

#### Changed
- While home is the LHD, the region map has no base cell, so no zone has a crossing "To FOB".
  The ops desk sells no defences aboard; they come with a FOB.
- Campaigns saved before this keep their FOB and play as before.

#### Fixed
- The contract board no longer offers jobs in a zone the company holds: not in the zone its FOB
  stands in, and not in a flipped zone while its seize-and-hold contract is out.
### A modern UI: new font, cleaner look, layout tools and explanations (Captain, 2026-10-20)

#### Added
- A UI font: Inter (SIL Open Font License, `fonts/OFL.txt`), in place of Godot's default. Body
  text is medium weight; headings, buttons and the HUD are semibold; titles are bold.
- Every menu explains itself. Each screen has a one-line subtitle saying what it's for, and a
  "?" button that opens how it works and its keys: main menu, pause, settings, inventory, loot,
  loadouts, medical (? or F1), shop, contract board, debrief, bug report and the base screen
  (each base page also has a line saying what it's for, and so does each terminal's ring entry).
  Buttons, settings, negotiation fields and lists have tooltips in plain words.
- Search, kind filter and sort in the inventory, the loot window and the loadout stash. They
  change only what's shown and in what order, never how anything is packed.
- Loadouts: each row shows the item's picture and its full description on hover. Drag a stash row
  onto the Kit column to put it on (as Wear, Mount or +1 would), or a kit row onto the Stash
  column to put it back.
- HUD layout: a new Settings tab with a size and an opacity for each part of the HUD (objectives,
  compass, squad list and command menu, radio and vehicle, weapon and armour, wound silhouette,
  objective markers) and a "Reset HUD layout" button. A bigger part keeps its corner of the
  screen.
- Medical menu: the arrow keys pick the body part (Left/Right) and the treatment (Up/Down), and
  Enter uses it. Rows are bigger and easier to hit.
- Command menu: the highlighted row has a background and an accent bar. With the mouse free, rows
  light up on hover and can be clicked. A footer lists the keys on tall enough windows.
- Item names in tooltips and the inspect panel are coloured by rarity (common, uncommon, rare,
  very rare), with the word in the stats line, for items that carry one (the loot work adds it).
- The ui suite checks that every menu screen has a subtitle, and that its open help still fits at
  1280x720 and a 2.0 UI scale. It also checks that the HUD layout at its biggest still fits, and
  that the reset puts it back.

#### Changed
- The theme is written by `tools/gen_ui_theme.py` from one palette (edit the script, not the
  .tres). It is cleaner: soft panel shadows, rounded corners, clearer hover, pressed and focus
  states, an amber main-action button and a red-edged one for actions that can't be undone, and
  restyled tabs, lists, pop-up menus, sliders, scroll bars, tooltips and key chips.
- Selling asks first. That covers the loadout stash's Sell, the base shop's Sell all, and Reset
  everything to defaults in Settings.
- The HUD's text is the size UiKit always said it was: 20 px, 16 px for its small lines, and
  28 px for the downed and killed titles. The theme had 18, 14 and 26. On short windows (1280x720
  at a 1.5 Menu and HUD size and up) the prompt, radio and vehicle lines drop to the small size
  so they still fit.
- Easier to read over the 3D view. The compass letters are 16 px, outlined, with brighter ticks.
  The ammo and armour lines are 16 px at 88% instead of 14 px at 70%. Objective markers are drawn
  at 95% near and 75% far (they were 70% and 45%), with outlined 16 px labels. The objectives list
  is outlined. The wound silhouette is about a third bigger.
- The item tooltips and inspect panel (ItemInfo), the armour readout and the medical menu use the
  shared palette instead of their own colours.

### Binoculars and the legs-still fix (Captain, 2026-10-20)

#### Added
- Binoculars you can look through. Press B on foot to raise them: a 7x view with a two-circle
  frame and a mil scale, and the weapon lowered. Press B again, sprint, or press a weapon key to
  lower them. You walk slowly and can't fire while they're up. Seated, B is still the vehicle
  view. The key can be rebound in Settings.
- Auto-walk: press = to walk forward hands-free. Sprint still sprints and A/D still steer. W, S
  or = again stops it, and so does going down or getting in a vehicle. Rebindable, and on the
  pad wheel.

#### Fixed
- AI no longer slide with their legs still at high frame rates. The model measured speed over
  one drawn frame, but bodies move on 60 Hz physics ticks. Above 60 fps, a jog read as standing
  still on frames with no tick, and as a teleport (zeroed) on frames with one. Speed is now
  measured over the time since the body last moved.
- F-07 (dynamic sim): a body only falls asleep when it isn't moving up or down. It no longer
  also has to report touching the floor, so patrols far away fall asleep again.

### Executive audit of 2026-10-19: ten findings fixed, three logged for Claude's side (cghath's side)

The audit is in `docs/audits/executive-2026-10-19/` (README, PART-1, PART-2). The repairs are in `FIXES.md`.

#### Fixed
- A2-01: a raid (by air or through a crossing) no longer picks up a job prepared for another
  zone. The job stays accepted and prepared for later.
- A2-02: saving during a deployment keeps the helicopters lost and their cooldowns, so a lost
  helicopter no longer comes back after a reload, and an expired cooldown doesn't return.
- A2-03: recon, hold, convoy, rescue and escort objectives carry on where they were after
  leaving and coming back to their zone or reloading a save. They no longer sit "active" for good
  with nothing running them. Their crews, waves, wrecks and convoy vehicles return once each, by
  their saved ids (`ScenarioCheckpoint`).
- A2-04: the days a debrief or a board wait passes now book base assaults and turn the rebel
  week too, as the base's own day advance always did. Several weeks at once each count.
- A2-05: the second fighter upgrade sends ten fighters, as paid for (6/8/10; 4/5/6 in a hot zone).
- A2-06: rebel fighters who follow the squad across a crossing stay rebels, and as many come over
  as were still up.
- A2-07: a raid banks the loot set down in the LZ, the holds and the gear on bodies carried out,
  and takes them out of the zone, as a contract does.
- A2-08: arriving in a remembered zone after travel keeps the travel time; a resumed save still
  keeps its own.
- A2-09: taking over a casualty's HX-1 while wearing an LX-3 is refused ("Take off your exo frame
  first") instead of deleting the HX-1.
- A2-13: the aim slowdown assist ignores civilians, captives and enemies behind walls.

A2-10, A2-11 and A2-12 are in Claude's files (the squad AI and vehicles). They are logged as F-04
to F-06 in `docs/audits/followups.md`, with a ready fix on branch `fix/a2-ai-vehicles`.

### Compound loot (cghath's side, 2026-10-20)

#### Added

- **Loot boxes by rarity, in the rooms where they'd be** (`data/loot_tables.json`,
  `WorldValuables`): every enemy site has box spots by room: an HQ's office desk and radio room,
  a compound's command-building desk, armory crate, footlockers, store shed and container, an
  outpost's bunker and ammo crates, a checkpoint's seized goods, village cupboards. The fitting
  rooms always get one, a few of the rest are picked per site. Each box rolls common, uncommon,
  rare or very rare by its site's stated weights (rare and very rare together 6% at a village
  up to 17% at an HQ), then a bundle from its table; very rare only in hot zones. The same zone
  rolls the same loot every visit.
- New `loot` test suite (local default list and CI).

#### Changed

- **Looted boxes stay looted:** caches and site boxes are saved with the zone (what's in them,
  and whether a strongbox was opened) instead of restocking on every reload.
- Site boxes replace the old "one piece of cash or intel, 18% something better" roll and the
  contraband swap; the HQ strongbox is unchanged.

### The tutorial, finished (cghath, 2026-10-20)

#### Added

- **New tutorial sections**, each step ticked off by what the game sees you do: **Medical** (a
  graze to bandage yourself, then a second one: call "Medic!" or "Treat me" from the command menu
  and a squadmate patches you up), **Tagging enemies** (Y, by radio), **Vehicles** (get in as
  driver, drive, take the gun seat, order the squad in, everyone out), **Rebel support** (ask a
  villager for work, give him supplies, Support > Rebels > Lookouts) and **Static guns** (pick up
  one of the M2's two loads, set it up, pack it up; shown once the game has static guns).
- Steps are grouped in sections, named in the panel's title.
- `tutorial` test suite: the tutorial as the menu starts it, every new step driven to the end.

#### Changed

- The tutorial's compound: its hostile patrol goes and the squad holds fire, so nobody fights
  while you learn; the target stands in the open yard (it stood inside the main building); an
  M-ATV, a villager and the static gun's loads wait south of the gate; the kit has two loose
  bandages.
- In the tutorial a villager answers "Ask if they need help" and "Give supplies", and the
  rebels' Lookouts answer the call, without a campaign.

### IFF marks you can read through a scope (Captain's tasking 7, 2026-10-19)

#### Changed

- **Armbands and helmet marks now show at combat range**: before, they disappeared past 45 m.
  They're now bigger blocks of flat colour (an armband over most of each upper arm, a band round
  the helmet plus a crown square, or a band round the head with no helmet) that glow slightly at
  dusk and are drawn out to 400 m. Blue is the company, green is allies (allied troops and
  rebels on our side), orange is the Black Ridge militia, and red is every other hostile.
  Civilians and HVTs have none. A body keeps its marks, and its ragdoll carries them. All the
  art is in `GearRig.iff_art`.
- **Under NVG, friend and foe look different**: friendly marks are IR-reflective and flare in the
  tube, while enemy marks are plain cloth and stay dark.

#### Fixed

- Eastern Concord troops in their Chinese kit wore militia orange (they share Black Ridge's
  urban camo). They now wear hostile red: every hostile's side is set when it spawns, from its
  camo and whose zone it is (`GearRig.hostile_tag`), and that travels with the spawn to every
  peer and into saved bodies.
- Faction skirmishers at odds with the company had no marks. Friendly rebels wore the company's
  blue.

### UI pass: debrief, salvage and the loadout menu (Captain's tasking, 2026-10-19, task 4)

- **Debrief and salvage** use the shared look: theme title, headings, figures and buttons, and
  no text under 14 px (the figure captions, table headers and footer were 12 to 13 px). A
  tagged pallet's or intel's buttons wrap under its line instead of running off a narrow panel;
  the salvage table's item column wraps and takes the room the numbers leave; claimed rows are
  green, rows that won't fit dimmed; casualties are listed one each, the dead in red.
- **Loadout menu** uses the shared look too. Nothing is clipped silently any more: the title,
  headings and status wrap; a person's button cuts with "..." and shows the whole line on hover;
  a drop-down is as wide as its prompt. It opens with the first person focused.
- **Base screen:** a squadmate's "HX-1: n/8 missions" no longer shrinks to nothing on the squad
  page. **Inventory:** an item's short name on a swatch is cut with "..." instead of breaking
  mid-word.
- **The `ui` suite checks harder**: at all 10 window sizes and 4 UI scales, every screen is
  checked for text under 14 px, text cut without "..." and a tooltip, squeezed text, controls
  outside what clips them, and overlapping controls. It now also fits a full debrief (salvage open
  and closed) and the loadout menu, and self-tests that each check still catches its problem.

### Economy balance proposal (cghath's side, 2026-10-20)

#### Added

- `docs/economy_proposal_2026-10-20.md`: measured economy balance numbers for the Captain to
  approve (contract pay, hot zones, intel, daily wages and upkeep, capped shock costs). Proposed
  only: no game number or code changed.
- `tools/economy_sim.tscn`: a headless economy simulation that plays short campaigns through the
  real board, debrief, bill and loot code with play profiles standing in for the fighting
  (`--runs`, `--days`, `--variant current|proposed|both`). Not a test suite; CI never runs it.
### CI flakes (cghath's side, 2026-10-20)

#### Fixed

- **Test flakes** that turned most CI runs red, each now waiting on what its check needs:
  world (the ground guard's own round no longer races the test's check; the fall spot is clear
  of rocks round the whole capsule), map (the staged squad stands still in the LZ before the
  extraction countdown), loop (the casualty lies out of the helicopter's own loading reach
  until the player carries him over), base_zone (confirming waits until the crossing counts the
  player in; a fly-on that doesn't board him now says where he and the helicopters are), voice
  (asking waits until the crosshair finds the soldier, and nobody else stands on the line).
- **A squadmate's slot no longer sits behind a wall from the lead for a moment** (casualty soak
  "stuck"): the 2 s hold that stops slots flipping by a doorway no longer keeps a slot (or a
  team's place) on the far side of a wall from the lead himself. Turning the corner by the
  compound's back wall, the second team's place and then Golf's slot sat outside it in turn,
  and he set off round by the gate.
- **Blood no longer falls through the ground under a body lying on it** (interaction, CI): a drop
  from the lowest skin, pressed a little into the ground, found no floor below it and lay as a
  pool cell 2.5 m under the yard; the floor is looked for again from just above it.
- **CI pinned to ubuntu-24.04** (both jobs): `ubuntu-latest` moves to Ubuntu 26 from
  2026-10-19, and the suites aren't proven there yet.

#### Added

- **A manual CI run can name its suites**: `gh workflow run tests.yml --ref <branch> -f
  suites="world map"` runs only those (space- or comma-separated); push and pull request runs
  still run every suite. `tools/check_ci_suites.sh` checks the workflow's list against the
  local default.

### Executive audit fixes and their review (cghath's side, 2026-10-17 to 18)

An outside audit of v0.4.36 (`docs/audits/executive-2026-10-17/REPORT.md`) found six defects;
all six are fixed (`FIXES.md`), then reviewed, and the review's problems fixed too.

#### Fixed

- **Killed garrisons stay dead after a reload** (E-01): bodies keep their post's spawn id, and a
  saved fallen-post ledger outlives corpse cleanup and extraction. Saves from before v0.4.10
  (callsign labels) migrate; v0.4.10 to v0.4.36 saves may duplicate a post once.
- **Cleanup never deletes the body a player stands beside** (E-02): it measures to where the body
  lies (`Soldier.body_point()`).
- **QRFs and hunters only spend the reserves they actually field** (E-03): the planned headcount is
  reserved, unspawned heads are returned, and short reserves are refused. A launch from two bases
  is approved once (one op, one radio order); later waves of it are paid silently. A shortage is
  still recorded, and a hunter with a stale last-known position still sends a probe.
- **A commander killed before command noticed him still leaves them headless** (E-04): HQ
  commanders register at spawn; death, cuffs, surrender or delivery all count.
- **Crow's Pass offers no contract from the enemy against itself** (E-05): Meridian is its client;
  the generator rejects hostile or unknown employers.
- **The draft-release helper can't touch a public release** (E-06): it reads the release state
  first and refuses public releases or unreadable state. Its test now enforces its "never upload
  or create" checks and can only reach an inert `gh` double.
- **One medic at a time walks in on a wounded HVT**: while one takes over from the escort, other
  medics leave it to him; if he goes down, another takes over.
- A packed massive neck wound can be clamped; a late joiner sees an already-held casualty in the
  held pose; an escort keeps caring for his HVT until a medic reaches the body; a bullet that
  wounds someone before a vehicle, armour or another body stops it reports the body hit.
- **CI**: the workflow is valid again (the runner job's log folder moved into its steps: GitHub
  doesn't allow `runner.temp` in a job's `env`); CI runs all 44 local suites, including voice,
  compass and audit_fixes, and a parity check fails if the lists differ.

#### Changed

- **Urban AI is cheaper**: building probes use a per-region index; building records are shared
  across scan heights (a building's answer no longer depends on which scan came first); zone
  navmesh chunks join by aligned vertices instead of proximity edges. A chunk baked from a
  module's stand-in is rebaked once the module's voxels are built. Town benchmark: average tick
  16.1 ms, p95 23.7 ms, building scans 58 ms a second (budgets 20 / 40 / 120; R0158).
- Helicopter clearance planning includes the tilted airframe and 2 m for contour lag (the 5 m
  clearance requirement is unchanged).
- Test fixtures: generated module variants, real body positions for reach, physical muzzles,
  seated-hitbox waits; the missions suite runs with the enemy commander on, except around the
  sections that drive the response by hand.
- The audit's probe scripts live outside the project (`Contractor-test-logs/audit-2026-10-17-probes/`);
  only its reports are in the repo.

#### Known gaps

- While a module is streamed out, a breach on a chunk seam can detour about 3 m until its voxels are
  rebuilt.
- Killed civilians and HVTs can still walk again after a reload when their body record was cleaned
  up (same cause as E-01, not yet fixed for people).
- On cghath's machine `map` (extraction countdown) and `ui` (vehicle readout) fail even on dev
  38f5825 (R0146); both pass on CI.
### Mission variety: sabotage done properly, every type played through (task 8, 2026-10-20)

#### Added
- **Sabotage hits what the enemy fights with**: a fuel store (the compound's generators and fuel
  drums; new steel drum stores at the HQ and the QRF base), a vehicle park (two or three technicals
  parked at an outpost, checkpoint, compound, QRF base or HQ) or the comms site's radio mast. A
  park counts once every vehicle burns, is a wreck or can't drive: a breaching charge set on each
  does it. Sabotage now comes up at checkpoints and compounds too, so contract zones get it.
- Tests: contracts checks the five mission-variety types on the board (in fitting zones, contract
  and hot); missions takes each from the board and plays it to the end through the real objective
  code (crews killed, crate carried out, position held, crew walked to the LZ, sites watched,
  charges set), plus a vehicle park left standing that pays nothing.

#### Fixed
- **The convoy's cargo bonus can be earned**: the crate is now a supply crate, and any one carried
  out counts. A crate carried in both hands kept no intel id, so the old hard case never counted.

### Day and night, weather: wave 7 S1 MVP (Captain, 2026-10-18)

#### Added
- Time of day per zone (`DayNight`, `scripts/world/day_night.gd`, a "DayNight" node in every
  level): a zone's `"hour"` (its data/missions.json entry or its definition; a deployed
  contract's own `"hour"` wins), 08:30 without one, passing at an hour per ten minutes in a
  contract zone (standing in the compound, the base and the range). The sun climbs and sets
  with it; at night a dim blue moon lights the level from the other side, and the sky (the
  procedural sky, or `zone_sky.gdshader` through its existing uniforms, no shader edit),
  ambient, fill and haze darken. A level at its own default keeps the look it built.
- Weather: `"weather"` the same way, one of clear, overcast, fog, rain, storm (`DayNight.WEATHER`,
  a row of data each): thicker Environment fog, a greyer, dimmer sky, darker nights, rain as
  GPU particles round the camera (not headless), slower spotting, a limit on how far anyone is
  seen (fog 150 m, storm 250 m, rain 400 m), footsteps carrying less in rain and storms.
- Darkness cuts AI spotting (`Spotting.sight_x`): `DayNight.darkness_at(pos)` (0 day .. 1 night)
  slows the spot up to 4x and hides anyone past the night's sight (60 m at full dark, 600 m at
  dusk) unless they fired in the last 1.5 s; one marked line is the hook for NVGs (wave 7 S2).
- Storms ground helicopters: `DayNight.grounds_aircraft()` answers `Supports.can_fly` through
  `CompoundLevel.weather_grounds_aircraft`, so the UH-60 supports refuse ("Helicopters are
  grounded: the weather won't let them fly") and a heli insertion goes on foot.
- Saved with the zone (`GameState.sky`, `"sky"` in the zone save; older saves have none) and
  replicated: a client asks the host when its level loads, the host sends it every 10 s.
- Dev keys (DevTools, the host): `;` moves the clock on 2 hours, `'` the next weather.
- `daynight` test suite (tests/daynight_test.gd), in tools/run_tests.sh and CI.
### NVGs, first slice (wave 7, S2; Captain: "Day and night, weather, and NVGs")

#### Added
- Night vision goggles by generation (`data/items.json` `nvg_gen1`/`nvg_gen2`/`nvg_gen3`,
  priced 3000/5500/9000 in `data/prices.json`): they mount on a worn helmet, and what's
  mounted lives in the helmet's item state (`"nvg": {"id", "lowered", "battery_h"}`), so it
  travels, saves and replicates with the helmet. Inventory: "Mount on <helmet>" on a carried
  NVG, "Remove <NVG>" on the helmet.
- The NVG key (`nvg_toggle`, U by default, rebindable; N is the next objective): flips the
  NVG down or up (`Soldier._server_toggle_nvg`, host-side); with none mounted it mounts the
  first one you carry and lowers it, and without a helmet it says to put one on.
- `Nvg` (`scripts/combat/nvg.gd`): `restores(viewer)` (0..1, the share of the darkness
  penalty to sight a lowered, powered NVG gives back; gen 1 0.6, gen 2 0.8, gen 3 0.9,
  Proposed), `is_lowered`, `is_on`, `fov_of`, battery helpers, host mount/remove/lower/drain.
  For day and night (S1) at integration: `dark *= 1.0 - Nvg.restores(viewer)` in spotting.
- Battery: drains in real hours of lowered use (6/10/14 h by generation, Proposed), charged by
  the host in 10 s steps; flat, the goggles stay down but show and restore nothing. Stowed, an
  NVG keeps its charge.
- `NvgView` (`scripts/combat/nvg_view.gd`): the wearer's own view through lowered, powered NVGs:
  green, brightened, with grain and a vignette, inside the tube's field of view (40/45/50 deg
  by generation, Proposed), the unaided eye's dim view around it.
- Test suite `nvg` (`tests/nvg_test.gd`), in `tools/run_tests.sh` and CI.
- With day and night (S1): lowered, powered NVGs give back their share of the dark's penalty
  to spotting (`Spotting.sight_x` scales darkness by `1 - Nvg.restores(observer)`).

#### Not yet
- No NVG model on the helmet (Captain's art side), no spare batteries or recharging, the NVG's
  mass isn't added to the helmet's, AI don't wear or use NVGs, IR illuminators and lasers
  later. A scope's picture isn't green through NVGs.
### Modular weapon attachments: grips, lights and lasers (wave 7 S3; Captain: "Modular weapon attachments")

#### Added
- Four attachments in `data/items.json` (type `attachment`, `stats.mount`, `stats.fits` = the
  weapon tags they fit; proposed prices in `data/prices.json`): Vertical Foregrip
  (`grip_vertical`, underbarrel, railed rifles, $250: x0.8 recoil, x0.85 aimed sway), Weapon
  Light (`light_weapon`, side, rifles and pistols, $350), Visible Laser (`laser_visible`, side,
  rifles and pistols, $450), IR Laser Aiming Module (`laser_ir`, side, rifles, $1100).
- `GunAttachments` (`scripts/combat/gun_attachments.gd`): the underbarrel and side mounts, next
  to the optic (`Optics`) and the muzzle (`Suppressors`), which keep their modules. What's on a
  gun lives in its item state (`state.underbarrel`, `state.side`, `state.side_on`), so it
  travels with the gun (stowed, dropped, looted, saved) and replicates with the inventory.
  `all_of(weapon, state)` gives every mount -> item id, optic and muzzle included. Host-side
  inventory actions `mount_attachment`, `remove_attachment` (target = the mount) and
  `toggle_attachment` (validated: the item is an attachment in your kit, the gun takes it);
  in the inventory: right-click it > Mount on <gun>; right-click the gun > Switch on/off,
  Remove. The mass and value of a gun include them.
- The weapon-light key, L (`Controls.KEYS weapon_light`, proposed): the light or laser on the
  gun in hand on or off. A light is a SpotLight3D along the aim, a visible laser a thin red beam
  to what it hits (`scripts/combat/gun_light_rig.gd`, placeholder look, drawn on every peer from
  the replicated state; no models on the gun yet). An IR laser draws only through night vision
  (`ir_seen`, the hook for the NVG work; nothing sets it yet).
- The AI spots a soldier with a light or visible laser on sooner (`Spotting.LIT` x0.4 with the
  beam towards it, `LIT_SIDE` x0.75 otherwise; proposed).
- Test suite `attachments` (in `tools/run_tests.sh` and CI): validation, the grip's kick and
  sway, mass and value, stowing and drawing, save/load and replication, the light and lasers,
  a suppressed shot, a 4x prism's zoom.
### Controller support and co-op assists (wave 7, S4; Captain: "Controller support and optional help for new co-op players")

#### Added
- On the pad wheel too: the NVG flip (U) and the weapon light or laser (L) from S2 and S3.
- A full gamepad layout (Xbox names; `Controls.JOY_BUTTONS`, `JOY_AXES`), next to the keys:
  move on the left stick, look on the right, RT fire, LT aim, A jump (the brake driving),
  B crouch, X reload, Y hold for the interaction menu (the right stick moves its cursor; click
  the right stick with Y held for yourself; downed, hold Y to give up), LB/RB lean, L3 sprint and
  hold breath, D-pad up primary, right sidearm, left grenade, down prone, Start pause.
- The pad wheel (`PadWheel`): hold View, point the right stick at a slice, let go: inventory,
  map, medical menu, quick treat, fire mode, launcher, rest weapon, inspect, optic zoom in/out,
  next objective, objectives list, vehicle view, get out, quick save. Stance adjust and
  push-to-talk orders stay keyboard-only for now.
- Right-stick look (`PlayerInput.update_pad`, `GameSettings.stick_look`): Controls tab rows for
  stick sensitivity, a round deadzone (15%), a response curve (1.6) and invert, saved in
  settings.cfg's new `gamepad` section; aiming, scopes, concussion and loaded sprinting slow it
  as they slow the mouse; seated, it turns the view as the mouse does.
- Co-op assists (`Assists` autoload), off by default and set by the host for the whole session
  (the Controls tab's "Co-op assists" rows, greyed out on a client; sent to every client and to
  late joiners; a client's request or anyone but the host's sync is refused):
  `aim_slowdown` (the stick turns at 40% over an enemy within 4 deg and 200 m; never the
  mouse) and `wound_hints` (a HUD line: your worst wound, where, what to use, whether you carry
  it). Objective markers were already on the HUD (the player's own setting), so they're not an
  assist.
- `controller` test suite (`tests/controller_test.gd`), in `tools/run_tests.sh` and CI.

### Squad roles and the Vantage Group rival PMC, first slice (Captain, 2026-10-17)

#### Added
- LX-3 presets (`data/roles.json` `lx3_capable`, `Roles.kit`/`apply_kit`'s new `lx3` argument):
  any existing role can be kitted with the LX-3 Assist Frame and Visor Helmet instead of the
  normal helmet without its stored role changing, so squad_ai.gd's role checks (`Roles.MEDIC`
  and so on) keep working. Not wired into AI auto-fill; a mission, loadout screen or roster hire
  opts a soldier into it deliberately, the same boundary `anti_tank` already draws.
- `heavy_gunner` (M240B) and `ammo_bearer` roles (`data/roles.json`): converted slots like
  `anti_tank`, not added to `fire_teams`. `SquadAI._maybe_resupply_gunner` hands the nearest
  belt-fed LMG carrier a box of whichever ammo his own weapon takes when he's run low and the
  bearer is already close (mirrors the medic-follow conventions near `MEDIC_FAR_M`, generalised
  by weapon tags (`lmg`, `belt`) rather than by role, so it serves Black Ridge's PKM gunner and
  any autorifleman's M249 too, not only Vantage's M240B — Captain, 2026-10-17, "the new roles go
  to the factions too"); it doesn't yet path to the gunner on its own. Black Ridge's own mix
  (`CompoundLevel.HOSTILE_MIX`) gained a PKM ammo bearer alongside its existing gunner, cast the
  same way (`hostile_role`, mirroring `rival_pmc_role`) at every spawn site (`EnemyResponse`,
  `Reinforcements`, `ZoneLevel`'s garrisons). A hostile cast as `heavy_gunner`/`ammo_bearer`
  skips the player-facing role kit (`CompoundLevel._make_soldier`): its own `hostile_loadout`/
  `rival_pmc_loadout` entry already carries the right gun and caliber, so re-kitting it would
  only stack a redundant weapon and the wrong ammo on top.
- `scar_h`, the SCAR-H battle rifle (`data/items.json`, `data/prices.json`): semi-automatic
  7.62x51, harder-hitting than the M4A1 with real recoil (`recoil_deg`). Renders through
  `VoxelArt.model_for`'s existing data-driven rifle model, no art-script changes. `ExoFrame`
  gained a `recoil_mult` (damps a working LX-3 wearer's recoil a little, read from
  `SoldierMovement.recoil_mult`) so the new recoil has somewhere to hook into instead of a
  parallel system; the heavy exo's own recoil interaction is left to its own branch.
- The Vantage Group, a rival PMC faction (`data/factions.json` `vantage_group`): fields modern
  gear (M4A1/SCAR-H riflemen, an M240B gunner and its ammo bearer) through
  `CompoundLevel.rival_pmc_loadout`/`PMC_MIX`, parallel to the Black Ridge militia's
  `hostile_loadout`. `EnemyResponse.enemy_faction`/`Reinforcements.enemy_faction` pick which
  mix a zone's patrols, hunters and reinforcement waves field; `ZoneLevel._on_contract_live`
  sets it from a live contract's `target`. Garrison spawns (`_spawn_queued_garrison`) and the
  tutorial compound's `HOSTILES` are left on the Black Ridge mix for this slice.
- Faction colours (Captain, 2026-10-17: "black for enemy pmc, tan for us"): new `VoxelArt` variants
  `black` (Vantage) and `tan` (the player faction), and Black Ridge's `urban` variant's patch
  colour changed from navy to orange ("give the militia we typically face early game an orange
  marker on their uniform instead of the same red one that's on the PMC"). Every friendly AI
  spawn site (`compound_level.gd`, `base_hub.gd`, `base_level.gd`, `aav_support.gd`,
  `heli_call.gd`) now spawns `tan` instead of `multicam`; Vantage's spawns (`enemy_response.gd`,
  `reinforcements.gd`) spawn `black` instead of `urban`. `Soldier.PLAYER_VARIANTS` gained `tan` too.
  Fixed in passing: the plain Ballistic/Bump/Heavy helmets never actually had the `faction_color`
  stat the LX-3 Visor Helmet already carried (`GearRig._rebuild`'s `set_cover`), so every
  faction's basic helmet rendered in one fixed colour regardless of variant; added it to all
  three (`data/items.json`) so helmets tint by side like the rest of the kit now does.
- Vantage's exo gear, gated by the contract's real 1-5 difficulty rating (`true_rating`, read in
  `ZoneLevel._on_contract_live`, not the briefing's `rated`, which can understate it): the LX-3
  Assist Frame and Visor Helmet from `PMC_LX3_DIFFICULTY` (4) on every PMC soldier but the exo
  pilot slot, which from `PMC_HX1_DIFFICULTY` (5) climbs straight into the HX-1 Assault Frame and
  its Walker Gun instead (`CompoundLevel.equip_hx1`, via `Inventory.put_on`/`unequip` — the same
  end state `ExoMech.server_enter`'s climb-in reaches, without playing out its 3.5 s animation,
  which a freshly spawned hostile has no reason to do; `ExoMech`/`ExoFrame` read the exo slot
  reactively, so piloting, size and pad armour all follow from the inventory state alone).
  Cutoffs (Captain, 2026-10-17, "Vantage gets exo suits and heavy exo suits but only on higher
  diffs"): LX-3 from a merely hard mission (a real but moderate edge); the HX-1 reserved for the
  single hardest tier, so it reads as a serious escalation rather than a mid-tier nuisance. First
  slice: the HX-1 pilot always spawns already suited; it doesn't climb into one standing in the
  world, and `Reinforcements.difficulty` has the same hook as `EnemyResponse.difficulty` but
  nothing sets it yet (contract zones' reinforcement waves, as opposed to hot zones' EnemyResponse,
  aren't wired to a contract's rating in this slice).

### Heavy exo: the HX-1 Assault Frame, first playable slice (Captain, 2026-10-16/17)

#### Added
- `exo_mech_heavy`, the HX-1 Assault Frame (`ExoMech`, `scripts/combat/exo_mech.gd`;
  docs/near_future_hardware.md 2.3): a heavy mech-class exo in the `exo` slot that is never picked
  up or put on from the inventory. Climb in from the interaction menu where it stands (3 s: you're
  put where it stood, facing its way, the hatch closing round you) and Climb out on yourself (the
  hatch opens, the suit is left standing where you were, you step down in front of it). Both clips
  are `CharacterModel.MECH_IN`/`MECH_OPEN`/`MECH_OUT`; the hatch (chest up, belly down, head unit
  back) follows them on every peer (`ExoMech.HatchRig`).
- Its armour is real `ArmorRules` armour (Captain's call over the doc's integrity pool): fifteen
  `VoxelArmor` plates on the parts they cover (Captain, 2026-10-17: AR500 steel throughout, IV chest, head unit, shoulders, caps and back;
  steel III belly; steel III++ forearms, thighs and shins; a III visor), their chips and integrity in
  the suit's state, like the LX-3's pads. A suit left standing is a `WorldItem` whose plates still
  take hits (into its state's "pads"), and climbing back in brings every chip.
- Real camo on armour: a `VoxelArmor` whose item says `"camo"` is painted in the wearer's camo
  pattern (`VoxelArmor.set_camo`, VoxelArt's own pattern), chips and scars still showing metal.
- Movement: it carries 260 kg (itself and 80 kg of kit); no sprint, jump, climb or prone; a fixed
  0.75 walking pace; no vehicle seat takes it. Its actuators take rounds like the LX-3's struts;
  disabled, the pilot carries all of it.
- `wg50_walker`, the WG-50 Walker Gun: a .50 BMG heavy machine gun (belt_50bmg) only a pilot can
  carry. It rides on the suit: climbing in puts it in your hands and your rifle on its rack.
  Held low and ready at the hip (`GearRig.LOW_READY_*`), up to the shoulder to aim. Voxel model:
  VoxelArt's "walker" style.
- One stands open on the vehicle range with its gun. Neither is sold yet: their price, repair cost
  and pilot training are the Captain's call (doc 2.3a).
- `mech` suite (`tests/mech_test.gd`) and `tests/mech_shots.gd` (art review shots).
- Captain's art round (2026-10-17, his refs): the suit is drawn 1.25x a soldier (about 2.3 m:
  `CharacterModel.suit_size`; its plates, hitboxes, eye and capsule grow with it, so it won't fit
  most doors), the pilot's body and kit hidden inside dark mechanical cores with only his head
  showing, the head unit sunk low between high shoulder humps and big pauldrons, heavier forearms,
  thighs and feet, a launcher pod on the back (art only), and the WG-50 redrawn as a six-barrel
  rotary.
- You get in from the back with the manual release (Captain, 2026-10-17, from AW's punch-out
  scene: "the full back opens, the legs too", like a zipper): standing behind it you hit the
  release panel (green button, warning triangle) and its back unzips, the power pack and back
  plates splitting at the spine, then the backs of the thighs, then the shins
  (`ExoMech.HATCH`, `ParkedHatch`); you're in it with your arms pushed into its sleeves, seen
  inside until it zips shut (`CharacterModel.MECH_RELEASE`/`MECH_IN`). Climbing out it unzips and
  you step back out behind it; it's left standing open. The back and the legs' backs are now
  their own AR500 plates (`back_r`/`back_l`, `thigh_back_*`, `shin_back_*`).

- Renamed the HX-1 Assault Frame (Captain, 2026-10-17: after the LX-3; the first name echoed AW's
  own Atlas).
- A downed suit, as in the scene (Captain, 2026-10-17): on a downed or dead pilot, a squadmate can
  **Punch out** (the release on its back; `ExoMech.server_punch_out`): the pilot comes out beside
  it and the suit is left lying face down, its back open (state "prone"). Kneel at its release,
  lie down into it, and it zips shut and pushes itself up onto its feet
  (`CharacterModel.MECH_RISE`, `ExoMech.RISE_S`). One lies face down on the vehicle range.

#### Fixed
- A round that met an armour piece's box but none of its voxels now carries on from just before
  that point, so a second piece whose box starts at the same spot is still met (`Ballistics`;
  found with the heavy exo's split leg plates).
### UH-60 walk-in cabin, helicopter doors, FFV riders, boarding and running out (Captain, 2026-10-17)

#### Added
- VTOL flight (`Helicopter.is_vtol`, data "flight": "vtol", "cruise_kmh"): the Petrel (320 km/h)
  and Razorback (270) bank into turns with the nose about level, accelerate and slow harder, and
  land by a straight approach to a hover then straight down: no J-hook.
- Hot drops: every insertion, and any landing with a known threat, comes in on a straight, low,
  fast approach with a hard flare and a quick let-down (`Helicopter.straight_plan`, `server_land_at`
  "hot"); a hot drop waves off only with more than 4 hostiles hitting it in 20 s (`HeliCall
  _shooters_hitting`). AI run out of the doors; it waits for them, then lifts.
- Fast-rope insertion (briefing: "Fast-rope from the hover"): a hover 12 m over the LZ, ropes from
  both doors, everyone down one at a time by the doors in turn, then away (`HeliCall._step_rope`,
  `Vehicle.server_fast_rope`, ropes drawn on every peer).
- The briefing picks the side a helicopter insertion comes in from (`Briefing.approach`,
  `HeliRoute.entry`'s side), re-planning its route.
- Pilots shown in the helicopters (drawn at the controls, `Vehicle._build_crew`).
- The Petrel's gun is an M2 .50 belly turret worked from the co-pilot's seat (`"gun"` "remote": the
  seat doesn't turn with it), crewed by a support crewman (`HeliCall._crew_gun`); its two door
  gunners are gone.
- Combat pilots: hit in flight, it jinks, drops lower and speeds up for a few seconds (`EVADE_*`).
- Fluid mantle (`SoldierMovement`): the ledge looked for along the way it runs, a jump into a wall
  or a press a step early counts, quicker on the move, one curve up and over, speed carried on.

#### Changed
- The UH-60 has no deploying boarding ramps (step "ramp": false: the mantle does it); sill riders'
  legs hang down to the ground.
- The UH-60M's cabin is a walk-in bay (`data/vehicles.json` "uh60" "bay": floor, walls, sliding
  doors, a step at each door; `VehicleArt`/`VehicleInteriors` hull and cabin rebuilt wider and
  taller), an open floor plan: only the 4-seat aft bench has seats; 4 kneeling spots (seat stance
  "kneel") and 3 standing spots on the floor, and 2 fire-from-vehicle riders per door sitting on
  the sill facing out, legs over the edge (seat "edge"; 19 seats: 2 pilots, 2 door gunners, 15
  passengers).
- Helicopter sliding doors (UH-60, Petrel, Razorback; `VehicleBay` door "roll_deg"/"pop"/"windows"):
  shut, each lies flush on its hull's skin (tilted to the flank's lean); opening, it pops out 1.5 cm
  past the hull, then slides back along its rail; each has windows after its airframe's design (the
  UH-60's two, the VTOLs' cabin window row carried across).
- FFV riders with the doors shut kneel behind the door facing out and move into their seat (the
  UH-60's: onto the sill) as it opens (`Vehicle._ffv_crouch`, `VehicleBay.open_fraction`).
- Kneeling (`Vehicle._kneel_feet`): the shooting side's knee up and its foot planted, the other knee
  on the floor (a right-hander's right knee up, a left-hander's left).
- AI take the FFV door seats first (`Vehicle._first_free_ffv`, also through `Helicopter.server_enter`).
- The Razorback: 3 FFV door seats a side (was 2), and its aft row of seats cleared into an exo bay
  with two standing spots (seat "exo", `Vehicle.exo_seat`/`_first_free_exo`; ~3 m headroom for the
  HX-1's ~2.3 m). Nobody else is put there; letting an HX-1 pilot ride there is the heavy-exo
  branch's to wire (its `server_enter` refuses suited pilots today).
- Riders on a seat with a canvas back (vehicles.json seat "back") sit back against it, nearly
  upright (`CharacterModel.SEAT_BACKED_PITCH`), their pack between them and the canvas
  (`Vehicle._pack_off`, `GearRig.pack_depth`).
- AI getting out of a walk-in bay on the ground run out (`Vehicle.server_run_out`, used by
  `HeliCall._unload` and `VehicleLayer.server_order_dismount`): up off the seat, a run to the door,
  down off the sill, out at the step's foot, instead of appearing beside the hull.

#### Fixed
- "That get anim is poor, it just floats up": getting into a bay seat from within
  `Vehicle.BOARD_FROM_M` of its door plays `CharacterModel.BOARD` for every peer. The door slides
  open, he steps up onto the sill (lead foot, push with a lean, trailing foot) with a hand on the
  grab handle by the doorway, walks in to his seat turning to face it, and sits down
  (`Vehicle._server_board`/`_board_pose`, `CharacterModel._boarding_bones`). Put in from far off
  (a mission's seating) or swapping seats, he's just seated as before.
### Air wing upgrades: the Razorback and friends (Captain, 2026-10-17)

#### Added
- Helicopter upgrade system (`HeliUpgrades`, `data/supports.json` "upgrades"): one-time
  company-wide purchases kept in the campaign save's economy section ("heli_upgrades"), bought
  from the base's Motor pool page (new "Air wing" section, `BaseUI._build_air_wing`, through
  `Economy.buy_heli_upgrade`/`server_buy_heli_upgrade`). Proposed prices, Captain's call:
  - Razorback heavy-lift VTOL, $120,000: transport, extraction and helicopter insertion calls fly
    `vtol_razorback` (more passenger seats than the Petrel; `HeliCall.model` from
    `HeliUpgrades.model_for`, its landing zones sized for it); resupply, medevac and cargo stay
    on the Petrel. A lost Razorback costs 1.8x the usual replacement. This is the "later unlock"
    docs/near_future_hardware.md 1.2 planned, through the existing money path.
  - Armoured cabin kit, $40,000: hits on a support aircraft do 30% less damage
    (`Vehicle.damage_mult`, set by `HeliCall` at spawn).
  - Fast turnaround crews, $25,000: every support's cooldown 40% shorter (`HeliSupports.cooldown_s`).
  A new campaign starts without them; outside a campaign the stock air wing flies.
- A contract's support budget is $23,000 a negotiation point (was $5,000; Captain, 2026-10-17:
  "enough to cover one heli exfil and the infil with one point in support": a transport's $9,000
  and an extraction's $14,000; `data/contracts.json` "support_per_point").
- AI getting into a helicopter take its fire-from-vehicle door seats first (Captain, 2026-10-17;
  `Vehicle._first_free_ffv`, through `Helicopter.server_enter` too, which picked the first cabin
  seat before).

### Floating site-box lootboxes, scope PIP black flash (Captain, 2026-10-16 playtest of v0.4.26)

#### Fixed
- Valuables/intel boxes at module loot spots (offices, command posts, desks -
  `WorldValuables.server_spawn_site_boxes`) floated about half a metre above the floor. They were
  placed at the same `ZoneModules.LOOT` anchor a `WorldItem` already rests at, but that anchor is
  a *drop* height for the `WorldItem` (a `RigidBody3D` that falls and settles onto the real floor
  on its own) - a `WorldCache` never falls, so it stayed exactly at the drop height instead of the
  floor. Open-terrain caches (`_spawn_site`) were never affected - they're placed straight on
  `ground_point()`, which `WorldCache`'s own shape already accounts for, same as `SupplyPallet`.
- A tube scope's or a flipped-up magnifier's picture-in-picture could flash black for a frame on
  a magnifier flip, an optic swap, or a window/viewport resize - all three resize the scope's
  `SubViewport`, and Godot doesn't repaint one in the same frame as a resize or its first creation,
  so `_draw_scope_pip` could read a stale or blank texture that frame (`GunSight._scope_stale`).
  Distinct from the by-design black ring mask around the glass (`_draw_ring`), which is untouched.


### Enemy high command, fuller zones, urban fights (Captain, 2026-10-17 night)

#### Added
- Enemy high command, Phase 2 (docs/enemy_high_command.md): the enemy commander judges you
  from what his men report (loud fire reads as more of you; noise far from a sighting gets a
  probe, not a hunt), spends finite reserves, probes and reoccupies lost sites, retakes ones you
  left a defender on, falls back when half his men are gone (outposts abandoned), and remembers
  how the zone went across deployments (cautious after losses, bolder after wins, easing back
  over the days). His orders go out on the enemy net (looted radios hear them).
- The commander is a person: the HQ's officer, or an HVT at the HQ in the enemy's uniform and
  medium armour with two bodyguards; hit the HQ and they run for a QRF base while he calls a
  relief force. Capture or kill him and the zone goes headless for 10 minutes. After you take
  out a QRF base, the follow-up contract is to capture him; the employer also warns you when a
  counterattack is massing. Dev tools: PgUp readout shows the commander's state.
- Eleven new contract zones, four on new terrains (highland moor, river valley, badlands),
  three on procedural terrains (two presets blended by the zone's seed), and two hot zones
  (Crow's Pass, Reed Delta).

#### Changed
- Outposts gain 2-3 buildings, villages 1-6 more houses and shops, compounds 1-2 buildings
  (generated round the hand-built core, where there's room).
- Woods sprawl: bigger, thinning to straggling trees at the edge, with outlying clumps.
- Towns are blocks, not a strip: back rows across alleys onto back streets, open lots,
  sandbag barricades and rubble in the streets. Defenders hold deep inside (back rooms), a
  reserve moves to the side being hit, hurt or isolated defenders fall back building to
  building, and in hot zones the commander sends a relief force into the streets.

### AI orders and rescues, dragging, enemy AI, voices, shop (Captain, 2026-10-17)

#### Changed
- Squad AI follows the order of command: a player's Move (until it gets there), Hold and
  ordered tactics come before fighting and casualty care ("B team not responding" was its own
  fighting and casualty care outscoring the player's orders). Holding, casualties near the spot
  are still seen to.
- Rescues under fire only when covered: the rescuer goes if it can throw smoke, a squadmate is
  putting fire on the shooter, the shooter is pinned or smoke is down; otherwise it fights and
  covers until one of those is true.
- Dragging and carrying: the AI turns to the way it's going (the casualty trails behind), and
  drags to the nearest spot that hides someone lying down, away from the shooter, without long
  detours.
- Enemy AI: sees and engages out to 300 m (was 200; insurgents open up at 240 m, regulars at
  280 m); pushes toward you only after 15 s out of sight (was 6), only to cover and only while
  its morale holds; shaken, it holds its cover instead of searching the kill zone.
- Voice callouts sit under the gunfire and ambience: 10 dB down spoken, 13 dB over the radio.

#### Added
- Shop: a search box (filters what's for sale and what you can sell as you type) and a "Sell
  from the stash" list with Sell and Sell all.

### LX-3 armour and helmet, the climb order, supports runner budget (Captain, 2026-10-16/17)

#### Added
- LX-3 armour pads: twelve Steel III++ pads on the frame (shoulders/upper arms, forearms, thighs,
  shins, stomach, collarbones, upper back, spine pack) that are real per-part armour, not art:
  each is a `VoxelArmor` piece on its body part's bone, chipping, denting, holing and wearing
  through under `ArmorRules` like any plate. A stop lands its impact on the part under it; a round
  that gets through goes on into the body. Their damage lives in the frame's item state, so it
  travels with the frame and repairs cover it. Spall-coated, and the frame keeps spall off arms
  and neck. Limb pads are rounded sleeves over front, outer side and back.
- LX-3 Visor Helmet (`helmet_lx3`, $6,500): a medium IIIA shell with a face guard bolted on below
  its rim (cheek plates on side hinges, a mask with a respirator block, a nape guard, a neck
  seal) and a black visor that stops fragments and spall only. Bullets hole the visor and plates
  like any armour, and the face shows through.
- Squad order "Climb up there" (Move > 9): selected AI squadmates go to a wall top or roof, climb
  every ledge in the way and hold up there. The jump key's mantle now works for AI too, and a
  working LX-3 frame climbs 1.3 m higher (3.2 m: compound walls, low roofs).
- The LX-3 and its armour take the wearer's side's kit colour (coyote with the contractors'
  multicam, matching the plate carrier), with panel seams and ridges.

#### Changed
- LX-3 Assist Frame: $45,000 (was $6,500), 14 kg with its pads (was 9). A starting company
  ($150,000) can field two LX-3 sets with money left over, not three.
- LX-3 frame art: slimmer and darker, hinge drums, pistons, boot stirrups and a jointed spine.
- `tools/run_tests.sh`: the supports suite gets 780 s (`suite_timeout`). Its host's own checks
  take about 460 s before the late-joining client's resupply flies, so 480 s killed it mid-flight
  and it read as a hang (R1500, R1503; green with the budget: R1504).

### Near-future hardware: VTOL dropship, VT-14/Razorback tiers, light exosuit (Captain, 2026-10-16)

Design doc: [docs/near_future_hardware.md](docs/near_future_hardware.md). Contractor's setting is
near-future sci-fi, not present-day only (Captain, 2026-10-16) — this is the first deliberate
near-future content, learned from *Call of Duty: Advanced Warfare*'s Warbird/Goliath reference art
the way `movement_rules.gd` learns from Tarkov's inertia; no COD:AW trademarked name ships.

#### Added
- VT-14 Petrel: a twin-ducted-rotor VTOL (`vtol_petrel`) replaces the UH-60M Black Hawk for every
  player-faction support call (resupply, transport, extraction, medevac, cargo). Flies through the
  existing generic `Helicopter` class unchanged (J-hook landing, contour flight) — new stats and
  voxel art only, no new propulsion physics. The UH-60 stays in the game as world content (rescue
  wrecks). Walk-in cabin, toggleable bay doors, folding boarding ramps, FFV door seats for players
  and AI gunners.
- Razorback VTOL (`vtol_razorback`, Captain's own name): a bigger, higher-capacity second VTOL
  tier, same bay/door/ramp/FFV treatment as the Petrel.
- LX-3 Assist Frame (`exo_frame_light`): the first exosuit tier, a new `exo` inventory slot worn
  over the vest/plates/pack (armor untouched). Working, it carries 30 kg of the load (speed/
  stamina see that much less load). Its struts can take rounds (into an arm/leg, or the spine pack
  from behind): worn down, it's disabled — no assist, full load back on the legs, its status light
  red instead of green. Its struts, hinges, cuffs, spine pack and shoulder pylons are drawn on the
  body (`ExoFrame`, `GearRig`).
- `tests/vtol_shots.gd`, `tests/exo_shots.gd` and `tests/shot_window.gd`: windowed screenshot
  scripts for vehicle/gear art that never take focus or the mouse (`ShotWindow.stay_out_of_the_way`),
  safe to run alongside someone else at the keyboard; `--headless` runs the same script as a quick
  sanity check with no window.

#### Changed
- Landing-zone ground clearance is now per-model (`LandingZone.clear_for`), not one constant: the
  Petrel's ducted pods clear the ground at 8.0 m, tighter than the UH-60's 9.5 m.

Suites: `vtol_shots`/`bay`/`heliflight`/`exo`/`mantle`/`smoke`/`armor` green. `vehicles` has 3
pre-existing failures unrelated to this work (none of the touched files differ from `dev`): 2
stale sound-name assertions fixed in this pass; one open-bed hit check diagnosed but left for a
follow-up (diagonal shot vs. the technical's bed wall geometry, not a VTOL/exo regression).

### MG/AR silhouettes, bolt-action snipers, suppressors (Captain, 2026-10-16)

#### Changed
- The PKM, M240B and M249 no longer share one `_rifle_mg` silhouette. Each has its own
  (`_rifle_pkm`, `_rifle_m240`, `_rifle_m249`, `VoxelArt`; `model_style` "pk"/"m240"/"m249" in
  `data/items.json`), built from reference photos: the PKM is wood-furnitured (handguard, grip,
  skeleton stock) with a perforated barrel jacket and its ammo box slung off the receiver's LEFT
  side; the M240B is all-black, the longest and bulkiest of the three, with a top-mounted carry
  handle over a top/right feed tray cover and a side-folding skeletonized stock; the M249 feeds
  from a box directly UNDER the receiver, has large top-mounted heat-shield vents, a small
  STANAG mag-well door, and a slimmer collapsible CAR-style stock. Irons are unchanged (AK-leaf
  for the PKM, rear aperture for the other two).
- The L85A2, C8 and HK416 no longer fall through to the generic AR silhouette they shared with
  the M27 (none set a `model_style` before). The L85A2 is a bullpup (`model_style: "bullpup"`):
  its magazine and long receiver sit behind the pistol grip, running to the shoulder plate with
  no stock past it, on a modern-upgrade flat full-length rail (a low red dot replaces its old
  prism sight). The C8 (`"carbine_short"`) is a shorter-barrel M4-pattern carbine with a longer
  exposed, notched buffer tube reading as collapsible. The HK416 (`"piston_ar"`) carries a
  piston rod over its handguard from a taller gas block, instead of the AR family's hidden
  direct-impingement tube.

#### Added
- Two bolt-action rifles: the Mosin-Nagant 91/30 (`mosin9130`, 7.62x54R, a PU scope, 5-round
  stripper clips — `clip_762x54r` — and its own wood-stocked voxel model with a visible bolt
  handle, `model_style: "mosin"`) and the Springfield Heatseeker (`springfield_hs`, a modern
  6.5 Creedmoor precision chassis rifle — a new `65cm_eldm` round, `data/rounds.json` — with a
  detachable 10-round box magazine, a folding chassis stock, an M-LOK handguard and a big
  precision scope, `model_style: "chassis_bolt"`). Both use a new `"bolt"` fire mode at 40 rpm;
  no new firing code was needed; the engine's existing per-shot rpm pacing already gates the
  next shot the bolt-cycle delay represents.
- Suppressors: an attachment (`Suppressors`, mirroring `Optics`) that mounts on a threaded
  weapon's muzzle from the inventory, the same way an optic mounts on a rail. Mounted, a shot
  is treated as suppressed — the quieter sound, a dimmer tracer and a much shorter alert radius
  the engine already had for a static "suppressed" stat, just never wired to anything players
  could attach themselves. `VoxelArt._with_suppressor` adds the can to a rifle's muzzle
  generically, over every silhouette at once, so a new one never needs its own suppressor boxes.

### Scopes are a real picture-in-picture (Captain: "better scopes and PIP", 2026-10-16)

#### Changed
- A tube optic's (LPVO, prism, DMR scope) magnified picture is now a genuine PIP: a `SubViewport`
  with its own `Camera3D`, synced to the player's eye every frame and composited into the
  eyepiece ring (`GunSight._draw_scope_pip`). The player's own camera no longer narrows its field
  of view while behind the glass — it eases back to the normal (peripheral) view instead, so the
  gun and its surroundings stay visible around the scope picture, the way a real scope only
  magnifies what you see through it. The reticle (mil-dot, LPVO cross, chevron/BDC) still reads
  true at any power; the glass picture renders at `GunSight.SCOPE_RENDER_SCALE` (0.65x of the
  ring's screen size, stretched to fit) rather than full resolution, to bound the added render
  cost. The first-person weapon/arms are on their own render layer
  (`PlayerInput.VIEW_MODEL_LAYER`) so they don't show up (huge, in the way) inside the magnified
  picture, and stay visible in the player's own (now unzoomed-while-scoped) peripheral view
  instead of vanishing entirely, as before.

### Squad callouts know what's actually going on (2026-10-16)

#### Added
- Contact calls are pre-rendered per clock position, close range getting its own urgent line
  (`Contact, two o'clock, 80 m`, voiced "contact_<clock>[_close]"); the subtitle keeps the exact
  distance, same as before. Enemies' contact calls get the same treatment and fall back to their
  plain line in Russian/Farsi (not translated for this pass).
- A squad member who's carrying intel calls out the kind of enemy site it just revealed ("Got
  the HQ marked!"), voiced per site type (IntelReveal.intel_found, Callouts).
- Reloading on the last magazine of a weapon's ammo gets an ammo-status line naming the weapon's
  class, not its caliber ("Last mag for the rifle!"): rifle, mg (belt-fed/LMG) or pistol.
- `Callouts.voiced_path` falls back from a dynamic id to its less specific prefix (down to the
  bare category) when no pre-rendered line exists yet, so a new template slot degrades to the
  old generic line instead of going silent; `tools/voices/gen_callouts.py`'s `LINES["en"]` has
  the new combos (contact x8 clock positions x2 ranges, 5 intel site types, 3 ammo classes) to
  render with Piper. Scope stays bounded ("nothing insane"): these three categories, English
  only, one phrasing each.

### The salt flats stop glaring (Captain, 2026-10-14)

#### Changed
- The Salt flats zone ("this terrain is an actual eye sore": a near-white pan brighter than the
  sky, meeting it at a hard line, nothing on it) is a grey-beige salt pan darker than the sky:
  damp patches, crust polygons and tyre tracks near you, shallow damp channels, gentle swells,
  mud, a berm and low rocky mesas round the edge, dead bushes, rocks and rubble at the margins
  and round the compounds and roads (the middle of the pan stays open), a softer sun and lower
  exposure, a warm horizon haze, and far ridges along the horizon. Other zones are unchanged.
  Numbers in docs/terrain_presets.md (Proposed); the world suite checks the pan's brightness
  against the sky, its relief and where its scatter goes.

### The red dot is a micro red dot's size (Captain, 2026-10-14)

#### Fixed
- The red dot sight (the M4A1's and Mk18's own, `optic_red_dot`) was a 9 cm long box with a
  3 x 4 cm window in a 4 x 5 cm housing, longer than the holographic sight, and in first person it
  stood out as a big box on the right of the view (and filled the lower right when the weapon
  pulls back near a wall). It is now an Aimpoint T-2 sized sight: a 3 cm tube 6.5 cm long round a
  clear 2 cm window, with its caps and brightness knob, on a slim riser and rail clamp, 5.5 cm
  from the rail to the top cap (`VoxelArt.optic_boxes`, `RED_DOT_LENGTH`). The line of sight,
  where aiming puts your eye and the dot, is unchanged; other optics, the rifle and the
  first-person view are unchanged. The gameplay suite checks its size and that its window is
  clear front to back round the line of sight.

### Vehicle interiors and windows (Captain's side, 2026-10-13)

#### Added
- Seated in first person you see a cabin instead of the inside of a solid hull: the M-ATV,
  MaxxPro, every technical (Hilux and Land Cruiser cabs), the AAV-7 and the UH-60 have their
  cabins hollowed and furnished at the models' 5 cm voxels: a seat under each enclosed seat's eye,
  a dash with the instrument cluster, radio and steering wheel before each driver, an instrument
  panel, cyclic and collective before each pilot, and windows you can see out of (glazed through
  the wall, tinted glass). The AAV's driver gets a vision slit in the bow and its cupolas' and
  weapon station's vision blocks are see-through; gunners' hatches are cut in the M-ATV's and
  MaxxPro's roofs (`scripts/art/vehicle_interiors.gd`).
- A new see-through palette entry (`VehicleArt.P.WINDOW`) on its own surface with a glass
  material; a burnt-out wreck's windows go opaque and dark with the rest of the hull.

#### Changed
- Hit volumes and protection are unchanged: interiors and see-through windows are drawn only in
  the canvas's `look`; the voxels rounds and fragments meet (`VehicleHull.first_solid`) are the
  same as before, windows included (still `P.GLASS`, still stopping what the hull stops). Damage
  marks (scuffs, scorch, a hole's ring) are only drawn where the look has a voxel, so a hidden
  solid cabin never shows as a black lump inside. The few visual-only differences: the M-ATV's
  cab back wall (rounds still pass where they did), the gunners' hatches, the AAV driver's slit.
- UH-60: the crew chief's and door gunner's eyes (x 0.95 to 0.72) and the four outer
  passengers' (x 0.9 to 0.75) moved in from the fuselage wall, which they sat in or outside of.

#### Known gaps
- Bradley, Abrams and AH-1Z have no interiors yet (nothing spawns them for players).

### Audit fixes: 26 findings of the 2026-10-13 audit (cghath's side, 2026-10-13)

The audit (`docs/audits/SUMMARY.md`, parts 1 to 3, at `fcae676`) found 3 high-priority and 23
medium findings. All 26 are dealt with: 25 fixed, A3-07 marked pending. Each has a regression
check in the suite that owns the code.

#### Fixed

- **Campaign saves are never deleted because they can't be read** (A1-01, high): an unreadable
  save, backup or interrupted write is renamed aside (`<file>.unreadable-<date>-<time>`) and the
  backup or a finished interrupted write loads instead. Only with nothing readable does a new
  campaign start; its old zone saves are moved aside ("orphaned") and the host is told where.
- **A missing save loads its backup** (A1-02, high), campaign and zone; saving checks every step,
  so the last good save is always on disk.
- **Loot all no longer duplicates an aid bag's contents** on a backpack (A2-01, high).
- Saves from another version, or with sections, records or voxel edits of the wrong shape, are
  refused (campaign) or skipped record by record (zone) (A1-03).
- A save that fails to write says "Campaign NOT saved: ..." instead of "Campaign saved" (A1-04).
- Malformed contract requests are answered "Bad request" instead of a host script error;
  negotiation terms must be plain numbers (A1-05).
- A reload no longer finishes on a different gun or launcher of the same model (A2-02).
- No IV below a tourniquet; with tourniquets on all four limbs only an IO is offered (A2-03).
- Muffled hearing clears when you leave the session or the level changes (A2-04).
- The medical menu's item list scrolls (wheel, arrows, page keys, scroll bar); off-screen rows
  can't be clicked; the panel fits shorter windows (A2-05).
- **The launcher has its own tile on the inventory screen**: what's loaded, Stow, Pack on top and
  Drop; drag to stow, drop or pack; a packed launcher dragged onto the soldier swaps with the one
  on the shoulder (A2-06).
- A pack dragged from the ground into a container is stowed, not swapped with your worn pack
  (A2-07); a crate or objective case dragged onto a container goes to the hands, as a click does.
- Squadmates picking their packs back up take their own pack by item, wherever it rolled (A2-08).
- "Scavenge that body" and AI scavengers use where the body lies (A2-09), and extraction counts a
  body or a downed squadmate where it lies (A3-03), per CLAUDE.md's reach rule.
- A raid's clear-area bonus waits until the target's garrison has spawned (A3-01).
- A civilian hurt only by a grenade's blast counts against the thrower, for fines and reputation,
  and so does a later death (A3-02).
- AI building scans no longer carry over between levels at the same coordinates (A3-04).
- A wall blown open in a zone module stays open for sight lines, rounds and AI paths after the
  module streams out (A3-05).
- Repair, refuel and salvage stop if the vehicle leaves the worker mid-job (A3-06).
- **Test runner**: an import that logs a SCRIPT ERROR or parse error fails the run even when the
  editor exits 0 (A3-08); logs are written straight into the kept run folder, and a run stopped
  part-way is a FAIL (A3-09). New `tools/run_log.sh` holds the logs parent, run number (taken under
  a lock) and branch-sha for the runner and the build tool.
- **CI** keeps each suite's own logs (import, suite, host and client) and uploads them as the
  artifact `test-logs-<suite>-attempt-<n>` whatever the verdict (A3-09).
- **Test builds** get their own numbered folder (`builds/contractor-<date>-<time>-B<number>-<label>-<sha>/`),
  an `index.txt` line and a kept export log; a failed export fails loudly (A3-10). With Zylann's
  Voxel Tools release template installed (`template_release/` beside the editor, or
  `CONTRACTOR_TEMPLATE`), a build also has a standalone `Contractor.exe` and a
  "Contractor (dev tools).bat" that starts it with `--dev`.
- Tests: the net test's client no longer deletes the host's save fixture (A1-06); the contracts
  replication test keeps a hostile in the compound so its objective stays active (A1-07).
- **A bearer ordered to move no longer lifts the casualty he just laid down, over and over**
  (found by CI on this branch; on dev too): the body's ragdoll settles up to about 2.6 m from
  the lay spot, which one check counted as "not there yet" and another as "laid". Both now use
  one test (`SquadAI._lies_at`, measured to `body_point()`). The squad suite's contact check
  waits for an AI physics step; the roles callout check uses squadmates tactics never speak
  through.

#### Changed

- **Faction doctrine numbers are pending** (A3-07): engage range, reaction, aim, bursts, frags,
  morale and movement in `data/doctrines.json` are marked pending in code and data; the AI doesn't
  use them yet (only the doctrine type shapes squad tactics). Wiring them in retunes every side's
  fighting, so it's left to Captain's tactics work.

#### Known gaps

- Quit from the pause menu still quits when the save fails (the failure is shown and logged).
- A civilian at a blast's edge with only ringing ears counts as a wounded casualty (A3-02; a design
  call).
- A peer that never streamed a module in still shows its original walls in that module's proxy
  until it streams in once (A3-05).
- Load-dependent test flakes seen during the work, also on the unchanged base: squad "Give me
  ammo", animations dragger hand placement, people's late-join client.

### Wave 5b: helicopter supports, AAVs, the LHD, the motor pool (cghath's side, 2026-10-12)

#### Added

- **Support menu** (command menu, 0): helicopter transport, resupply and extraction, and an AAV
  submenu. `Supports` (`scripts/supports/supports.gd`) is the seam: support commands, where
  supports launch from (the LHD, the friendly FOB's side, else the map edge), and a can-fly
  check for weather later.
- **AI-flown UH-60 Black Hawks** (`Helicopter`, a `Vehicle`): take off, cruise about 90 m above
  the ground following the terrain, approach, flare, land and leave by their origin. Rotors
  turn and the engine sounds; smooth for clients and late joiners. 7.62x54R and launchers hurt
  them; a rotor, engine or crew kill brings one down, and it crashes and burns with everyone
  and everything aboard. A support lost is gone for the rest of the op (Captain).
- **Calls**: at your map marker, at the spot you look at, or on smoke of the right colour
  (resupply green or yellow, transport green or blue, extraction purple). Without a mark it
  comes in and loiters near the squad, keeping away from fire, until it sees its smoke.
  Supports cost money (the contract's support budget first, then cash), have cooldowns, one of
  each kind at a time.
- **Landing safety**: a spot too steep (over 15°, the design doc), built up, blocked or with
  people on it lands at the nearest safe spot within 100 m (Captain); enemy fire never moves it.
- **Resupply** sets down a supply pallet: magazines and rounds for the squad's weapons, medical
  items, grenades and smoke (`data/supports.json`).
- **Transport** (hot zones only) picks up the squad (players through Left Ctrl, AI ordered in,
  the downed loaded) and flies it to the caller's map marker. Hot-zone briefings offer each
  insertion point by Black Hawk: the squad starts aboard and is flown in.
- **Helicopter extraction** is extraction's ride: its landing spot is the extraction point; the
  squad, the AI brought along, the downed, cuffed or friendly HVTs and the items set down in the
  point go aboard, and lifting off ends the deployment with what's aboard in the report. The
  countdown extraction still works without it.
- **The LHD** lies offshore on every zone whose terrain preset has a sea (a placeholder ship,
  never attacked); supports start from its deck. Inland they come from the friendly FOB's side
  of the map. New preset `amphibious_coast` and test zone `coast`.
- **Amphibious vehicles**: the AAV-7 floats, swims at 13 km/h on its waterjets, steers and drives
  up the beach. Other vehicles flood and stall past their fording depth.
- **The AAV support** (Support, AAV): an AAV and its AI crew from the LHD (it swims ashore) or the
  FOB (it drives in) for $12,000. Orders: move there, hold, follow me, squad get in, dismount,
  return to base. Its gunner fires the M2. Hot zones and coastal contract zones; refused in
  mountains, on ground too steep, or when the company can't pay. One at a time; lost with
  everyone and everything aboard, and no other comes that op.
- **Motor pool**: the company's own vehicles between deployments (campaign section
  `motor_pool`), starting with one M-ATV. Pick them on the briefing to bring them; ones that
  extract with the squad come home with their damage, fuel and cargo; ones left behind are
  lost. The base's motor pool sign lists them and books repairs (money and days). The base hub
  itself is unchanged: the friendly-FOB conversion waits for a decision.
- **Vehicle QRFs** in hot zones (Captain's hook): some QRF waves ride in technicals, get out short
  of the contact and leave the gunner on the DShK.
- **State dumps** list each vehicle (driver, passengers, damage, fuel, AI order) and each support.
- **Dev tools**: with `--dev`, outside a deployment, helicopter calls are free and transport flies
  outside hot zones; `]` calls an AAV to you anywhere, free.
- **Tests**: `supports` and `aav` suites (host and client).

#### Changed

- Vehicles hold grades up to 35° within their grip (an AAV-7 used to stall on 8°).

#### Fixed

- A navigation chunk that is all sea no longer errors (an empty triangle list).
- The `antiarmor` M-ATV spall check is deterministic; the `missions` charge check follows how the
  man actually moved on rocky ground; the `aav` swim check samples deep water only.

#### Known gaps

- The helicopter crew is simulated (no crew bodies after a crash); no rotor wash, door guns or
  autorotation. Typed grid references only as a command argument (`grid:<ref>`).
- On Captain's `coastal_lowland` sea the LHD sits about 50 m off the beach in shallow water; a
  wider, deeper sea would suit it (Captain's call). AAVs there are untested beyond the test zone.
- Players can walk on the seabed; the map doesn't draw the sea.

### More bone simulation (Captain's picks, 2026-10-12)

#### Added

- **Open and closed breaks, a pelvis with a pelvic binder, collarbones, hands and bullet ribs** (`WoundModel` "Bone sim" constants, `BodyMap.BONES`): a bullet or fragment break is open with a chance by round class (a femur's higher), a fall's mostly closed; an open break bleeds on its own and needs a bandage or gauze besides its splint (two tasks in the plan of care, the medical menu and AI care), and moving on an unsplinted broken leg can turn a closed break open (noted in the session log) and raises a femur's internal bleed. A broken pelvis bleeds heavily inside and can't walk or stand (crawl, or be carried) but can still shoot; the new **Pelvic Binder** item (`data/items.json`, in the medic's kit) cuts its bleed and the legs stay out until the mission ends. A broken collarbone adds rifle sway and slows aiming down sights (pistols unaffected; a sling, the splint, eases it), a broken hand counts as a broken arm, and a bullet through an unplated chest can crack a rib. No spine injuries.

### Triage cards and bleeding HUD (2026-10-12)

#### Added

- **Triage cards**: the medical menu has none / minimal (green) / delayed (yellow) / immediate (red) / expectant (black) buttons for the casualty (host request `Soldier._server_set_triage`, reach-checked to `body_point()`, replicated in `net_state` "tg"; shown in Check condition). AI responders take immediate before delayed (and uncarded) before minimal, expectant last. Also: a small body silhouette in the HUD corner while you have an untreated bleed, fracture or tourniquet.

### Sound (Captain's side, 2026-10-12)

#### Added

- **Sound** (`Sfx` autoload, `data/sounds.json`, docs/sound.md): generated, stylised sounds for
  gunshots (near and far, suppressed), bullet cracks passing close, impacts (dirt, plate,
  body), explosions, flashbangs, reloads, throws and footsteps; heard from each player's own
  position, delayed by distance, within the ranges the AI hears. Real recordings in
  `res://audio/sfx/` override any sound. `tools/export_sounds.gd` writes them as WAV files.
  New suite `sound`.

### Session-log event lines and a movement-test fix (2026-10-12)

#### Added

- **Session logs now record casualties, care and returns to base**: a soldier going down or
  dying (who, cause, body part, who hit them and from how far; `Vitals.last_cause`), every
  treatment (`Soldier._treat` / `_timed_care`: treater, patient, item, part, done / interrupted
  / refused and why) and Return to Base / revert (`BaseHub`).

#### Fixed

- **Movement suite flake** (stand-up after the ragdoll): the test put the body back before the
  ragdoll had finished standing it up where it lay, so the walls were built round the wrong spot.

### Bug-report key and AI overlay (2026-10-12)

#### Added

- **Bug-report key (Insert, any build)**: a note panel (Enter saves, Esc cancels) writes
  `report-<n>.txt` and `report-<n>.png` into the session's folder: the note, time, zone and
  seed, `SessionLog.state_text` (every soldier, the AI's intents) with the player's inventory
  and wounds, and the last log lines. `BugReport.save(note, node)` is the callable the tests use.
  The pause menu shows the key. `SessionLog.state_text` now includes the local player's
  inventory and wounds.
- **AI debug overlay (Delete, dev tools, host)**: labels over AI within 80 m (the nearest 16)
  with intent, status, target, combat mode and suppression, and a line to where each is heading
  (`SquadAI.destination()`), refreshed 4 times a second.

### Medical menu, slice 1 (Captain's side, 2026-10-12)

#### Added

- **Medical menu on H** (`MedicalMenu`, `scripts/ui/medical_menu.gd`; inspired by ACE3's): opens
  on the person you look at within treatment reach (measured to `Soldier.body_point()`), else
  on yourself. A body diagram of the 14 parts, clickable, coloured by state (bleeding by
  severity, untreated, treated) with TQ, splint, dressing, seal and IV/IO markers; the chosen
  part's injuries in words and every medical item you carry, greyed out with the reason when
  it can't be used there now; choosing one sends the same `_server_treat` request as the
  interaction menu's Treat (and Remove tourniquet its own). Signs in words (numbers only with
  a pulse oximeter). An activity log, local to the treater for now (what you chose, and the
  changes seen while the menu was open). H or Escape closes it; while open it has the mouse
  and the keys. Reads replicated state only, so it works on clients. Test: medical suite
  "Medical menu (H)".

#### Changed

- **Quick-treat moves to Shift+H** (`quick_treat`, `Controls.SHIFT_KEYS`), same behaviour as the
  old H. The `use_medical` action is now `medical_menu`.

### Terrain presets (2026-10-12)

#### Added

- **Terrain presets** (`data/terrain_presets.json`, `docs/terrain_presets.md`): coastal_lowland (with a sea along
  one seeded side), salt_flats, desert_wadi (carved riverbeds), rocky_ridge, scrubland, temperate. Chosen by the def's
  `terrain`, name hints or region, and carried in the def. `ZoneScatter`: seeded rocks, scrub and trees by zone
  area (MultiMesh; large rocks and trees have collision and nav boxes).

### Wave 5a: vehicles and anti-armour (cghath's side, 2026-10-12)

#### Added

- **Captain's vehicle models in the game**: `VehicleArt` (14 voxel models at 5 cm: UH-60,
  AH-1Z, AAV-7, MaxxPro, M-ATV, Bradley, Abrams, seven technicals) copied from his asset
  repo to `scripts/art/vehicle_art.gd`. Physics layer 7 is "vehicles".
- **Vehicles** (`Vehicle`, `scripts/vehicles/`, numbers in `data/vehicles.json`): host-simulated
  Jolt bodies with raycast suspension; wheeled ones steer with the front wheels, tracked ones
  skid-steer. Clients send throttle, steer and brake and see smooth replicated movement.
  Fuel, an empty tank, jerrycans.
- **Seats**: per model (M-ATV 4 + gunner, MaxxPro 6 + gunner, technical cab, bed and gunner,
  AAV-7 3 + 21, Bradley 3 + 6, Abrams 4; the UH-60's seats wait for the helicopter supports).
  Get in, switch seats and get out through Left Ctrl action points (doors, ramp, cargo,
  service). Squadmates take "Get in that vehicle" and "Get out" (command menu: Mount). A downed
  or dead body can be loaded into a seat and pulled out again.
- **Cargo**: each vehicle carries an inventory with litre and kg limits, loaded and unloaded
  through Left Ctrl; it feeds the mounted guns' belts (.50 M2 on the MRAPs, DShK on the
  technical).
- **Vehicle damage**: hit zones (hull, engine, wheels or tracks, fuel, crew, cargo) with armour
  by class. Small arms bounce off armoured vehicles; 7.62x54R and up penetrate or disable them
  (Captain's rule); a technical's doors stop nothing; IFVs and tanks stop .50 on most faces.
  A round that gets through carries on into the people inside. Engine hits slow then stop a
  vehicle, wheel and track hits cripple it, fuel hits leak and can start a fire. Hits carve
  holes and scorch into the vehicle's own 5 cm hull.
- **Fire and wrecks**: a burning vehicle kills whoever stays aboard and destroys its cargo,
  then becomes a blackened wreck that can be salvaged for parts. Vehicles and wrecks are saved
  with the zone and come back when the campaign returns to it.
- **Field service**: timed repairs with a repair kit, spare wheel, track links, engine parts or
  a battery.
- **AI drivers**: `server_drive_to` and `server_follow_path` on the navmesh, with stuck
  recovery.
- **Bodies and vehicles**: a vehicle wakes a settled ragdoll ahead of it and pushes standing
  soldiers aside; running someone over is blunt trauma through the wound model.
- **Vehicle range**: a main-menu debug level with an M-ATV, MaxxPro, technical and AAV-7, and
  `VehicleLayer.server_place_parked` so zones can park vehicles.
- **Anti-armour launchers** on a new launcher slot (key 3): AT4, RPG-7 (PG-7V HEAT, OG-7V frag),
  Javelin (hold aim 2.5 s to lock; top attack climbs and dives onto the roof, or direct attack),
  MAAWS (HEAT, HE, HEDP), NLAW (flies over and fires down, or direct), SMAW (HEDP, thermobaric).
  Rounds fly as host-simulated projectiles with motors, drop, arming distance and
  self-destruct, seen by every player. Data in `data/warheads.json`.
- **Warheads by round type**: shaped charges penetrate armour by mm (V1 decides what that does
  to the vehicle) and the jet kills whoever is in line inside; HE and HEDP blow craters in
  walls, HEAT bores a narrow hole, thermobaric clears rooms; fragments and overpressure wound
  people through the wound model; a direct hit is lethal.
- **Backblast**: a cone behind the tube, lethal close in and injuring further out; a wall or a
  vehicle right behind reflects it onto the shooter, and a small room fills with it. Javelin
  and NLAW soft-launch.
- **AI launchers**: insurgents sometimes carry an RPG-7 and use it on vehicles and groups behind
  cover, never on a lone soldier in the open ("Backblast clear!"); a squadmate with a launcher
  fires on order (command menu: Action, "Fire launcher there").
- **Items**: launchers and rounds (RPG-7 and its rounds loot and sell-only), jerrycan, spare
  wheel, track links, repair kit, vehicle battery, engine parts, .50 and 12.7x108 belts.
- **Tests**: `vehicles` (host and client) and `antiarmor` suites, including launchers against
  the real vehicles.

#### Fixed

- **Launchers against real vehicles** (wave 5a integration): a shaped-charge jet that gets
  through a hull goes on into the cabin and kills whoever is in its line; the crew takes one
  spall pass (the vehicle's), not two; rockets meet a vehicle only where its 5 cm hull is, so
  one through an open bed or over a hatch flies on; riders in open seats take blast and
  fragments like anyone, enclosed seats shield; a launcher can't be fired from a seat; a
  shooter who leaves while the round flies no longer breaks it; the AI stops firing at
  burning vehicles. Proposed: `Warheads.TOP_PROBE_M` 3.0 m.
- The `people` suite's client sometimes never reported: the host pushed its checklist when
  the client first connected, and a connect that timed out while the client was still
  building its world lost it (and Main reloaded the scene under the test). The client now
  joins by itself, retrying, and asks for its checklist once in; the antiarmor client too.

#### Known gaps

- The launcher slot has no tile on the inventory screen yet (that screen's layout is Captain's
  side's); key 3 and Alt+G work.
- No AI gunners or turret rotation yet; no crash damage between vehicles or against walls;
  grenades and charges don't damage vehicles except a charge placed on one.
- Structure edits are lost when a VoxelWorld block unloads far from every viewer.

### Session logs (Captain's side, 2026-10-12)

#### Added

- **Session logs** (`SessionLog` autoload): every playtest (editor or build) writes a numbered
  session (P<number>) beside the test runs: every error and warning with its backtrace, what
  the game prints, slow frames, network events, zone changes and every message the player was
  shown. The first time each kind of issue happens (an error, a warning, a soldier fallen out
  of the world) it saves a state dump (every soldier, the AI's intent and target, the hot
  zone, the last log lines) and a screenshot. The folder ends PASS or FAIL; one that crashed
  stays RUNNING. The pause menu shows the session number. New suite `session_log`.

#### Changed

- `HotZoneDebug.readout(from)`: the hot-zone readout without the overlay, for the dumps.

### Wave 4B part 3: the hot zone; debugging rules (Captain's side, 2026-10-12)

#### Added

- **Hot zones** (16 km², `ZoneDef.generate_hot`): one enemy HQ, a comms site, 1-2 QRF bases,
  outposts, road checkpoints, villages, roaming patrol routes; campaign zones `ridge_hot` and
  `coast_hot`.
- **The enemy's alert** (`Alert`): the enemy only knows what its people see, hear and radio in,
  with report delays (a man killed first never reports), sound ranges (suppressed much
  shorter), check-ins, bodies found, a last known position that grows less certain; areas and
  the zone go normal, suspicious, alerted, engaged and cool down slowly. No meter on screen.
- **Pressure** (`Pressure`): points from what the squad does (firefights, kills, our blasts,
  wiped patrols, objectives, sites taken out, alarms; quiet decay; +1 per 30 min), halved with
  the comms mast down; tiers at 10/20/35/50.
- **The enemy's response** (`EnemyResponse`): roaming patrols (one goes to look at a report),
  patrols doubled and checkpoints closed when alerted or under pressure, the QRF from the
  nearest living QRF base when engaged (at once on standby, after a turnout if caught cold; a
  second at tier 2; none with every base gone), hunter teams at tier 3 (flank, track, smoke;
  fewer with officers dead), the HQ reinforcing its sites at tier 4. Nothing spawns in the
  squad's sight.
- **Looted enemy radio chatter** (`RadioChatter`): carry an enemy handheld radio to hear the
  enemy's net, until they switch frequencies.
- **Radio contracts** need a field radio (PRC-152) in the squad: "Radio for a contract" in your
  own menu.
- **Escape menu**: Resume, Return to Base (revert: back to just before deploying), Return to
  main menu, Quit.
- **Dev tools** (`DevTools.on()`: debug builds or `--dev`): hot-zone readout (Page Up), enemy
  clock skip (Page Down); test builds ship "Contractor (dev tools).bat".
- **Debugging rules** (Captain, `docs/debugging.md`, `CLAUDE.md`): every run keeps numbered
  logs by date with PASS/FAIL in the name; `tools/run_tests.sh` keeps them in
  `Contractor-test-logs` beside the main checkout.

#### Changed

- Hot zones drive reinforcement waves from the enemy's alert (no timer); waves head for the
  last known position.
- Debug instant extraction moved to Shift+End (End alone opens the board); K and Shift+End
  work behind `DevTools.on()`.

#### Fixed

- The HQ's watchtowers faced inward and garrison men faced anywhere: towers have parapets on
  their outer sides, posts face out, gate guards stand behind the sandbags facing the gate.

### Ragdolls, clean test sessions, clothing, intel fog (Captain's side, 2026-10-11 late)

#### Added

- **Ragdolls** (Captain): downed (unconscious) and dead bodies, AI and players, fall and lie
  as host-simulated ragdolls (`Ragdoll`: torso, head, thighs, shins, upper arms, forearms,
  anatomical joint limits), replicated as `CharacterModel.ragdoll_net` and kept by saves.
  Bodies rest on each other instead of clipping; a settled body freezes, so nothing shoves
  it; the living step over a body or pile up to 0.75 m. Hitboxes, wounds, blood and charges
  follow the ragdoll. Carried or dragged it goes; put down it falls again.
- **First-person arms**: your own forearms and hands on the weapon (there were none for
  anyone), mirrored for a left-handed shooter.
- **Clean test sessions** (Captain): the menu's play and test entries spawn players in their
  role's kit with one tidy row of spares (`CompoundLevel.CLEAN_LOOT`); the test contract
  starts fresh every time. The campaign keeps roster gear.
- **Roadmap**: item catalogue plan, dog tags (Captain: they count), and bases (Captain: no
  player-built FOB; friendly faction FOBs with portable company modules; replacement troops
  flown in from the LHD at a cost) in `docs/ChrisPlan_handoff.md`.

#### Changed

- **Civilians, HVTs and hostages wear plain clothes** (Captain): one flat colour, no camo,
  patch, belt or knee pads; HVT outfits by side, role, site, region and captivity
  (`PersonLook.outfit`). The chest box and the HVT head band are gone.
- **Briefing intel is never spot on** (Captain): estimates are off by what the intel's
  accuracy allows; under 60% accuracy quality reads as a word.
- **AI hold while a briefing is open**, so nobody dies before reading it.

#### Fixed

- A downed or dead body's capsule shoved itself out of anyone walking into it, and one going
  down beside another was pushed on top of it.
- Blood that landed on a body or item floated once that moved; it now sticks to it. Pools
  stop at edges.
- A downed (unconscious) player could crawl.

### Wave 4B part 2 follow-ups (Captain's side, 2026-10-11)

#### Added

- **HVT escorts** (Captain): command menu Action > "Escort that HVT" (look at him) puts the
  nearest of the selected squadmates on him, at most two (`Squad.order_escort`, SquadAI
  `Intent.ESCORT`); "Stop escorting" or any movement order takes them off. The first leads
  him along with the squad (waiting when he lags), the other stays close behind him; in
  contact both fight from beside him, between him and the threat. If he bolts they react
  after 0.6-1.6 s by skill (slower suppressed, not while pinned or blinded), run him down
  with weapons lowered and grab him within reach with a 55-80% chance per try; a fast
  enough runner still gets away. Downed, they carry him with the squad.
- **A wounded HVT is a medical priority**: one in the squad's hands (escorted, captive,
  hostage, down, carried) is a casualty for the squad's AI; his escorts treat him first
  with what they carry, and a free medic is pulled to him ahead of other casualties and
  takes over. Proposed numbers.
- **Garrisons sized from the true force** (Captain): a deployed contract's target module holds
  the contract's true enemy count (`ZoneLevel.garrison_size`, from `Contracts.enemy_force`), so
  an understated briefing really bites; other modules keep their 4. Extra posts stand beside
  the module's own at the first clear spot (a capsule check, `_extra_post`); a module that
  streamed in before the briefing is topped up when the contract goes live.
- **HVT capture without zip cuffs** (Captain: cuffs stay a base-shop buy, but the job must be
  doable without them): a hostile HVT who gave up (or was downed and carried) follows when led
  and counts when brought in uncuffed. An uncuffed one needs babysitting (`HvtAI._check_bolt`):
  nobody from the squad up and not pinned within 6 m for 4 s, and every 2 s he may take his
  surrender back and run (`PeopleLayer.server_take_back_surrender`), the odds climbing to 0.6
  over 12 s alone; a fight around him gives a small chance even when watched; the more it
  hurts the less he tries, and badly hurt he stays put. Cuffed HVTs never bolt. Proposed numbers.
- **Real names** for HVTs, hostages and civilians (`Names.mission_person`): HVTs from the
  target faction's nation (`factions.json` "nation"), hostages from mixed nationalities (US,
  UK, Canada and the region), civilians from the region's own people (`contracts.json` regions'
  "nation"); given names for the region and the wave 6 nations.

#### Changed

- The HVT capture brief explains the no-cuffs option. The placeholder name lists in
  `contracts.json` are gone.
- `docs/ChrisPlan_handoff.md`: suicide bombers and VBIEDs in wave 6 (VBIEDs after wave 5 V1);
  backlog: zip cuffs lootable in zones.

### Wave 4B part 2: missions in zones (Captain's side, 2026-10-11)

#### Added

- **Captain's first four mission types** (`data/contracts.json`, from
  `docs/mission_brainstorm.md`): **raid** (destroy a weapons cache or an AA gun; bonus: leave
  no fighter standing), **HVT capture** (a hostile HVT taken alive to extraction, 90 min clock;
  bonus: their phone), **hostage rescue** (a friendly hostage brought out, 75 min clock; bonus:
  clear the guards) and **intel grab** (a laptop or hard case carried out; bonus: the
  documents). They replace the four placeholders. Pay, enemy ranges and the clocks are Proposed.
- **Contracts in the generated zones** (seam 3): every contract zone is a world-scale
  `ZoneDef` generated from a fixed seed (`MissionRegistry.zone_def`), the same layout every
  visit, and a contract targets one of its modules (`module_id`); its objectives sit at that
  module's sites (`contracts.json` "modules": sites for the compound, outpost, village and
  checkpoint) wherever it stands in the zone (`Contracts.module_origin`). Accepting one deploys
  into its zone. A cache's voxel count can be `"auto"` (`ZoneModules.solid_voxels_in`).
- **New module art for raids**: an AA emplacement in the outpost (sandbag ring, twin-barrel
  steel gun: a grenade barely chips it) and crate caches in the village's plank shack and by
  the checkpoint's booth.
- **People reach the contract** (seam 5): when a contract goes live (`Contracts.contract_live`)
  the people layer puts its HVT or hostage (named, carrying their own intel), its intel pieces
  (each with its own intel id: only that piece counts), civilians going about their day in the
  zone's modules, and a delivery point at each landing zone. The People ledger feeds the
  contracts: deliveries, intel carried out (banked mid-zone), civilian casualties (once per
  civilian; the 8th voids), and a dead HVT or hostage (`People.hvt_lost`) fails its objective.
  An HVT brought to a landing zone the squad picked counts too.
- **Timed objectives**: "time_limit_min" on a mission type; the HUD shows the minutes left and
  the objective fails when the clock runs out.
- **Breaching charges, placed like Arma Reforger's** (Captain): Shift+G to the charge, G holds
  it up as a ghost lined up with the surface you look at (2.5 m), Fire sets it, G or RMB puts it
  away. It sticks to anything: the world, a person (it rides their body part) or a moving body
  (vehicles from wave 5 get `server_explosion`), the hook for suicide bombers on foot and in
  vehicles later. After the fuse (Proposed 10 s): a frag blast and a breaching carve; a raid
  target within 1 m is destroyed (`Charges`, `Objectives.server_charge_blast`).
- **Reinforcements sized from the true force** (seam 7): `Contracts.reinforcement_tuning`
  (first wave sooner and waves bigger the higher the true rating, living hostiles capped at
  the true count plus 8, the waves' skill from the true quality), started with the contract.
  In a zone they come in at the terrain's edge nearest the squad but at least 350 m out
  (`ZoneLevel.reinforcement_edge`).
- **The briefing** marks objectives at their module and what intel knows of the enemy there.
- `missions` test suite (21 suites now).

#### Changed

- The contracts test registers its own compound-clearing type for the clear-area checks.
- `breaching_charge` fuse 5 s -> 10 s (Proposed).

### Female soldiers (Captain, 2026-10-11)

#### Added

- **A female body for soldiers** (`scripts/art/voxel_art.gd`, `_head_f`, `_torso_f`,
  `_upper_arm_f`, `_forearm_f`, `_leg_f`, `_thigh_f`, `_shin_f`): the same Stormworks
  low-poly style, on the same frames and pivots as the male parts, so animations, plates,
  carriers, helmets, pouches and held weapons fit. Her own proportions, loosely after real
  averages: drawn at 93% of the male model (about 1.68 m to 1.80 m), with gear and hitboxes
  scaling with her, and her own shoulder joints (`CharacterModel.FEMALE_SCALE`, `FEMALE_SHOULDER`; see
  Changed below). Narrower shoulders and slimmer
  deltoids and arms, a narrower waist over fuller hips (0.36 m) with a seat, a chest under a carrier that
  rides forward over it (see Changed below), slimmer legs, smaller hands and boots, and a smaller
  head with a softer jaw, thin brows, lashes, lips and the hair in a low bun under the
  helmet's rim, with hair framing the face.
- **Choosing the body:** `CharacterModel.body` ("male", the default, or "female"),
  `Soldier.body`, and an optional `"body"` in `CompoundLevel.spawn_soldier` data (it rides
  the spawn data, so every peer builds the same body). `Soldier.body_record` saves it, so a
  dead soldier's body keeps it. `VoxelArt.body_part(part, body)` names the model
  ("torso" or "torso_f"). Players can't pick it yet (no menu option).
  Male models are unchanged, byte for byte.
- **Who's a woman follows the force's norms** (`scripts/ai/demographics.gd`, Captain's call): an AI
  soldier's chance follows their nationality and role. A medic is at their nation's overall
  share and every other squad role at 0.3 of it, since women are fewer in combat arms. Overall
  shares: US 17.7% (DoD 2023), Canada 16.3% (DND 2024), UK 11.9% (MOD 2024), Russia about 4%,
  China about 4.5%. Iran (women only in medical posts) and insurgent cells: none in field
  squads. The PMC follows each contractor's nation. A US rifleman is a woman about 5% of the
  time, a US medic about 18%. Russian surnames take the feminine form (Ivanova).

#### Changed

- **Her own shoulders** (Captain: "their own proper shoulder value"): `CharacterModel.FEMALE_SHOULDER`
  (0.20 m out, 1.5 cm lower than his 0.25 m, replacing `FEMALE_SHOULDER_X` 0.225 m) and
  `CharacterModel.shoulder_of(body)`. Her arms hang against a narrower ribcage without
  passing into it; rounded deltoids cap the joint and the shoulder line slopes down from the
  neck instead of the male square shelf. The kneel/reach solver (`reach_pose`) uses her
  shoulder too.
- **Her chest higher and fuller** (Captain: "too low and too small", then "reduce ... or make
  the carrier fit like irl"): two low-poly lobes high on the chest, 0.135 m in front of the spine
  (the male chest: 0.11 m).
- **Carriers fitted to her like real ones** (Captain's photo refs: "the carrier conforms to the
  body while the plate sits inside"): she wears `VoxelArt._vest(tier, torso_fc, true)`
  ("vest_f:<tier>"): the cummerbund is her own torso shape plus padding, the back panel sits
  `FEMALE_CARRIER_BACK` (2 cm) further in against her slimmer back, the heavy rig's side
  pockets sit in at her sides (`carrier_side_inset`). The front panel ("vest_f_front:<tier>")
  sits flat `FEMALE_CARRIER_FRONT_OUT` (1 cm) further out, padded inside down to her chest and
  belly (no gap under it), with cummerbund wings from its edges round her sides to the rear
  panel. Under a carrier her bust is held flat and pushed out to the sides ("torso_fc",
  `CharacterModel.set_carrier_worn`, which GearRig calls). Everything on a panel goes with it
  (`GearRig.carrier_fit(face)`): plates, MOLLE pouches by their face, name tape and slung rifle
  (front), pack and pack straps. Male carriers are the same as `art/carrier-fit`'s.
- **Her hips and waist** (Captain: "more natural instead of like a Mii"): one smooth curve,
  widest at the hip joints (0.35 m) and easing in to a 0.27 m waist about 20 cm up (it pinched
  from 0.35 to 0.26 m over 10 cm); the seat is broad and flatter across the hips, setting out
  from the small of the back, instead of a ball.
- **Medical voxel wounds on her body:** `BodyVolume.pivot_at(part, body)` puts her arm shapes
  at her shoulders (hits were judged, and blood drawn, 2.5 cm off at the male joint); the
  host builds both bodies' shapes at start (`BodyVolume.warm(["", "female"])`). Wounds test:
  her upper arm is judged at her own shoulder.

### Respawns paid cash first, then the support budget; who fields the US heavy kit (Captain, 2026-10-11)

#### Changed

- **Bought respawns** (past the deployment's free ones) cost more each time (`prices.json`
  "respawn_rise": $1,000, $1,500, $2,000...) and are paid from **cash first, then the
  deployed contract's support budget**, then on credit (`BaseHub.server_count_respawn`).
- Plans: the AH-1Z, MRAPs, Bradley and Abrams are fielded by the US and by close allies that
  operate those exports (the UK and Canada: MRAPs only). Reputation tiers, ripple, decay and
  allied troops point at the mission brainstorm, where they're decided.

### The mission brainstorm in the repo (Captain, 2026-10-11)

#### Added

- `docs/mission_brainstorm.md`: Captain's mission brainstorm (Oct 10), exported from claude.ai.
  Wave 4B part 2 takes its mission types and debrief from it. The design doc and plans link it.

### Net test smoke check and the voxel smoke roadmap (Captain's side, 2026-10-11)

#### Fixed

- **Net test:** the purple smoke the host throws before the client joins now starts
  `SMOKE_AGE_S` (3 s) old and the client checks its copy is at least that old. It used to
  check for over 2 s and failed whenever the client joined quickly (1.6 s), though the copy
  was right.

#### Changed

- `docs/ChrisPlan_handoff.md`: CS2-style voxel smoke on the roadmap (wave 7, S5).

### Wave 4B part 1: the mission loop wired end to end (Captain's side, 2026-10-11)

#### Changed

- **One bank:** the base runs on the `Economy` autoload (`BaseEconomy` is a thin adapter; the
  stand-in cash is gone). The base terminal's shop is `Economy.server_buy` into the armory
  stash (`purchase_sink`), salvage and what's brought out land in the stash (`stash_sink`), the
  respawn price is `prices.json` "respawn".
- **One clock:** `BaseHub.day()` is `Economy.day()`. Resting, deployments and travel move it
  through `Economy.advance_days`; the roster's recovery and the hiring board follow
  `day_advanced`; the roster's wages are the weekly bill (`Economy.wages_provider`) with base
  upkeep and loans. A deployment's days pass once. Older saves give their base day way to the
  economy's.
- **Board -> base -> zone:** accepting a contract starts its prep at the base
  (`BaseHub.begin_prep_contract`; "Prepare deployment" on the board and "Prep" on the base
  screen pick another held one). Deploying takes the squad into the zone, where the briefing
  opens for everyone on the zone's map; its start makes the contract live, moves the squad to
  the insertion point and opens extraction.
- **One end of a deployment:** extraction's report settles it once
  (`BaseHub.end_deployment`, an `Extraction.END_GROUP` handler): the debrief (pay, clawback,
  fines, reputation, days), then the roster (MIA, recovery contracts, gear home), then everyone
  back at the base. People bring their own gear home; bodies carried in and items set down at
  the point go to the stash.
- **Clawback terms** (Captain): each contract states what a void does to the advance: kept
  (none), prorated (the share of required objectives not done is given back) or returned
  (full). Fixers' jobs keep it, the safe job returns it, the rest are rolled; a lenient client
  pays less (`contracts.json` "clawback_terms", replacing `void_claws_back_advance`). Shown on
  the board, in the briefing and in the debrief.
- The board in a campaign has no debug deploy, end or reset buttons.

#### Added

- **Recovery contracts:** a squadmate left behind alive puts a recovery contract on the board
  (`Contracts.server_add_recovery`: no pay, `recovery_offer_days`). Deployed on it, they wait
  where they were left, join the player who reaches them (`BaseHub.FOUND_M`) and come home
  recovered if they're inside the extraction point; anything else writes them off.
- `Contracts.contract_accepted`, `contract_closed` (with `EXPIRED` for an offer that ran out),
  `server_abandon_deployment` (a save made mid-deployment); objective templates may carry
  their own site (`"params"`).
- Tests: base "The loop" (board -> prep -> briefing -> extraction -> debrief -> base, and a
  recovery end to end); contracts: clawback terms.

### Carriers fit the body that wears them (Captain, 2026-10-11)

#### Changed

- **Plate carriers are cinched to the wearer** (Captain: "make the plate carrier fit more like
  it would irl"): the cummerbund is the wearer's own torso shape plus `CUMMERBUND_PAD` of
  webbing and padding (1.5 cm medium, 2.5 cm heavy), so it takes in at the waist and lies on
  the body instead of standing off it as a box; the light rig's straps lie on the body; the
  heavy rig's side plate pockets reach in to the cummerbund (the plates stay where they were).
  `VoxelArt._vest(tier, torso)` takes the wearer's torso spec (the male one by default), so
  another body shape gets a carrier fitted to it.

### Medical voxel wounds on the current dev (merge)

#### Changed

- **World test:** the doorway shot aims at the pelvis; at 0.6 m on the man's centre line it
  passed between his legs, which hits on the body's real shape (BodyVolume) now allow.

### A hired squadmate is one person (Captain, 2026-10-11; wave 4B groundwork)

#### Changed

- **Hiring rolls the whole person once:** each contractor on the board has a first name,
  a surname, a nationality (US, UK or Canada by weight), a shooting hand (11% left) and a body
  type (`Names.person`), shown on the board and the roster ("Brandon Stewart, CA, right-handed").
  The roster keeps it, and **every deployment spawns that same person**: their surname on the
  name tape, their nationality and their hand (`Roster.identity`, merged into the spawn data by
  `BaseHub.server_spawn_roster_squadmate`). Before, the board's name and the name tape were
  rolled separately and didn't match. The body type is always male on `dev`; the female-model
  branch decides it in `Names.body_for`.
- **No two name tapes in the company match:** a new hire whose surname is taken gets another
  from their nationality (`Roster.unique_surname`).
- **Older saves:** a member hired before this keeps their roster name ("Dale Okafor" -> OKAFOR
  on the tape) and gets a nationality and hand once, seeded by their callsign
  (`Roster.ensure_identity`).
- **Bodies keep the person:** a body's record saves and restores the name tape, nationality and
  hand (`Soldier.body_record`, `CompoundLevel._make_body`).
- **Tests:** the base suite checks the board, the hire, a clashing surname, an older save, the
  deployed squad, a fallen squadmate's body and a second deployment.
### The test runner can't pass a broken suite any more (audit L5-01)

#### Fixed

- **`tools/run_tests.sh`:** a suite passes only if it exits 0, prints its `<NAME> TEST PASSED` line
  and logs no `SCRIPT ERROR`. Before, a script that failed to compile (a parse error) or crashed
  mid-test could read as passed, or hang the run forever. Each process now has a timeout
  (`SUITE_TIMEOUT`, default 480 s) and fails as hung past it; the import must succeed; the net
  and world hosts are judged too, with their output kept.
- **`tools/test_runner_check.sh` (new):** checks the runner against a fake engine: a pass
  passes; a failure, a script error with exit 0, a missing summary, a hang and a failed import
  fail. CI runs it as its own job, and the rerun-on-failure step has a timeout now.
### A squadmate that gives up its slot leaves what it was handed (audit L1-03)

#### Fixed

- **Outside the campaign, an AI whose slot a player takes drops what it holds beyond the kit it
  spawned with:** items players handed it, what it scavenged, an objective item, in a pile at
  its feet with their state (part-used magazines, damaged armor). Its own kit goes with it, so
  a join doesn't hand out free gear. Before, it all vanished. (In the campaign a roster member
  already keeps everything.) Stacks unlike its starting kit go first, so a handed-over
  7-round magazine is the one left, not one of its own full ones.
- **Test:** roles suite (salvage and a part-used magazine left behind, no kit items).

### Medical: impact pain is eased by morphine (audit L3-01 check)

#### Added

- **Medical test:** pain from a round stopped by armor (impact, no wound) asks for morphine,
  a dose eases it well beyond its own fading, no second dose is asked for once there's nothing
  left to ease, and light impact pain uses none. The audit's finding (a kit used up on impact
  pain it couldn't treat) was about the old stopgap kit; wave 3's morphine already treats it.

### Late joiners, bad input, reloads, sprinting, fire cadence and the menu (audit L2-01, L2-02, L3-02, L4-02, L6-01, L8-01, L10-01)

#### Fixed

- **Late joiners see smoke already out,** at its age (`CompoundLevel._send_smoke_to`); before,
  the AI could hide in a cloud they couldn't see.
- **Late joiners see a carried or dragged body as not solid,** from the replicated carry state.
- **Bad coordinates are refused:** a shot, throw or squad order from a NaN or infinite point, or
  with no direction, is turned down before a round or grenade is spent (`Soldier.usable_point`,
  `usable_direction`); map markers, extraction points and reports check theirs too.
- **A reload started before dying no longer finishes on the respawn rifle.**
- **No sprint without room to stand tall:** under a low roof a low stance stays at walking
  speed and uses no stamina.
- **Shots bunched by the network still count:** the host's fire gate lets its schedule run up
  to 0.15 s behind (`Soldier.FIRE_BUNCH_S`), so correctly paced shots aren't dropped under
  jitter, while a flood still fires at the weapon's rate (2 at once at most after a pause).
- **Main menu:** centred in the window, and it scrolls in a small window instead of running
  off it.
- **Tests:** gameplay (bad input with a control shot, reload across a death, fire cadence),
  net (smoke and a dragged body for a late joiner), movement (no sprint under a low roof).

### Saves can't lose progress (audit L1-01, L1-05)

#### Fixed

- **Partly taken loot stays partly taken:** taking some of a level-placed stack (no room for the
  rest) now saves what's left; before, a reload brought back the full stack.
- **Saves go through a checked temporary file** (`GameState.write_safely`): the zone and the
  campaign are written to `<save>.tmp`, read back, then swapped in, with the previous save
  kept as `<save>.bak`. A save that is cut off or unreadable loads its backup instead.
- **A save is checked before it replaces anything** (`GameState.read_save`): a section of the
  wrong type refuses the whole save; a single bad record (an unknown item, a position that
  isn't three finite numbers, a count below 1, a broken body) is skipped with a warning and
  the rest loads. Before, such a save could leave the host without a player.
- **Tests:** the gameplay suite checks the partly taken stack across a reload, the backup, the
  fallback from a cut-off save, bad records and a wrong-typed section.

### AI soldiers have names, on name tapes (Captain, 2026-10-11)

#### Added

- **Names:** every AI soldier gets a surname and a nationality (`scripts/ai/names.gd`), and
  is called by it everywhere a callsign used to show: callouts ("Martinez: Reloading!",
  "Man down! Thomas is down"), the HUD squad list, the command menu, AI status lines and
  the interaction menu. The node keeps its callsign (Alpha, Bravo...) inside the code.
  - **Your PMC** hires US, UK and Canadian contractors (60/25/15). Each pool is that
    country's most common surnames.
  - **The insurgents** use regional surnames. Russian, Chinese and Iranian pools are ready
    for the faction wave.
  - **Names are stable and unique:** a callsign keeps its name, and no two soldiers on a
    side share one. A recruit who replaces a fallen squadmate gets a name of their own.
- **Name tapes:** the surname, in capitals, on a tan tape on the carrier's loop panel. It
  replaces the flag patch there.

### Weapon holds, and left- or right-handed shooters (Captain, 2026-10-11)

#### Added

- **Left-handed shooters:**
  - **Players** pick "You shoot: Right-handed / Left-handed" on the main menu. The pick is
    saved between sessions (`user://settings.cfg`) and sent to the host on join, like the role.
  - **AI soldiers** are left-handed at the real rate for men, 11% (about 10.6% of people
    overall, men about 1.23 times as likely as women; `scripts/actors/handedness.gd` has the
    sources). Each roll is seeded by the soldier's name, so a callsign keeps its shoulder.
  - **What mirrors:** the rifle shoulder, the firing and support hands, the sling, the
    holster, the draw, and your first-person hip view.
- **Everyone sees you shoulder your weapon:** aiming (`Soldier.is_aiming`) is replicated.

#### Fixed

- **Weapon holds (third person):**
  - **Stock in the shoulder:** a rifle's butt sits in the firing shoulder's pocket. Aiming,
    it points straight out and the head dips onto the optic.
  - **At the ready,** the stock stays in the shoulder and the muzzle dips 30 degrees, in
    across the body. Before, the rifle floated in front of the chest with its stock inside
    the body.
  - **Hands on the weapon:** the support shoulder comes forward as a shooter's does, and the
    support hand takes the handguard within reach (up to 0.52 m from the butt). Both hands
    land on the weapon in every hold.
  - **Pistols** are pushed out two-handed at the eye line when aiming, and held low in front
    of the chest at the ready.
  - **Slung:** the rifle hangs diagonally across the front of the carrier, clear of the
    pouches, with the stock under the firing-side armpit and the muzzle at the other thigh.
    Before, it hung straight down beside the arm.
  - **Bladed stance, no floating shoulder:** holding a rifle at the ready or aiming
    (standing or crouched), the upper body turns 23 degrees (`CharacterModel.BLADE`, 0.4 rad)
    about its own up axis, support shoulder forward, as a shooter stands; the head and the
    weapon turn back by as much, so they still face where the soldier looks. The hitboxes,
    plates and carrier turn with the body. The support shoulder joint now comes forward only
    a little, inside the deltoid (`SUPPORT_REACH` 0.04 in, 0.06 forward). Before, it moved
    14 cm forward and floated in front of the torso. The shoulder pockets turn with the
    chest, so the stock stays in the shoulder and both hands stay on the weapon. Treating
    yourself takes the wound from the squared-up body, and no longer turns you towards
    your own arm.
  - **Slung rifle lies flat:** on its sling the rifle now lies on its side against the
    chest, ejection port out and the magazine pointing down towards the firing-side hip,
    4 cm closer to the carrier. Before, the optic stuck straight out and the magazine
    pointed into the chest.
- **Net test:** the remote treatment check waits up to 1 s for the treat animation to
  replicate (action_net comes on its own sync, after the vitals), instead of checking in the
  same frame. It failed now and then under load.
- **Tests after the dev merge:** the people, base and world suites looked soldiers up by
  callsign where the game now shows the name on the tape (`display_name()`); they pass that
  name in or read it. The map suite clears the compound's hostiles before its clients join:
  an unarmoured client shot down while standing about left a body the extraction report counted.

### Stormworks-style character models (Captain, 2026-10-11)

#### Changed

- **Soldiers rebuilt in a low-poly Stormworks style, still in voxels** (`scripts/art/voxel_art.gd`):
  body parts are lofts with flat faces and 45-degree bevelled edges, written in centimetres
  and built in 0.5 cm voxels, on the same joints as before, so animations, helmets, plates,
  pouches and held weapons fit unchanged. The trunk now reaches down to the crotch (the hips
  10 cm below the hip joints) with the belt at the waist, so the legs show from where they
  do on a real body. A boxy head with a flat face: eyes, brows, nose, mouth and ears.
- **Camouflage by faction:** MultiCam (soft brushed blotches, a few dark flecks), woodland
  (blotches with black branches), desert (broad drifts) and urban (grey woodland),
  domain-warped so the shapes flow.
- **Plate carriers enclose their plates:** rebuilt in 1 cm voxels with a fabric pocket round
  each plate and a lip over its edges. A plate in its pocket takes the carrier's fabric
  colour (`VoxelArmor.cover`); chips and holes still show the plate under the torn cover.
  The heavy carrier has side-plate pockets, a collar and a groin flap.
- **Captain's first look:**
  - **Chin:** the jaw is now a 45-degree chamfer under a straight face. Uneven slopes stepped
    unevenly at 0.5 cm and showed as bands across the chin and face.
  - **Shoulders:** the torso has deltoids. Above the chest they flare out at 45 degrees to
    0.26 m, over the shoulder joints, and the trapezius runs flat in to the neck. The upper
    arms taper into them, so the arms hang out from under the shoulders and turn under them.
    The arms used to hang 4 cm clear of a narrow trunk, like separate columns.
  - **Plate carriers less blocky:**
    - **Shape:** the pockets have bevelled edges and a chamfered top, and the cummerbund takes
      in at the waist.
    - **Shoulders:** the shoulder straps are padded pads that arch over the deltoids, where
      they used to be solid blocks.
    - **Details:** PALS webbing rows across the front and back panels, seams round the plate
      window, a loop panel with a flag patch at the top of the front, and a drag handle at the
      top of the back.
    - **Backpack straps:** a worn pack's padded straps come over the shoulders and down the
      front edges of the plate pocket, with a sternum strap.
  - **Front pouches** sit on what's behind them: on the plate face (in the pocket's window),
    or on the cummerbund beside the pocket. They used to float 2 to 4 cm off it. The medium
    carrier's TQ holder moved out to the pocket's edge.

### Wave 4A of the build plan: the mission loop, first half (cghath, 2026-10-11)

Five parts built in parallel, ported onto Captain's wave 3, reviewed, and integrated. The loop
isn't wired end to end yet (wave 4B): each part has its own entry point on the main menu.
Mission types are placeholders (clear a compound, recover an HVT, retrieve intel, destroy a
cache) until Captain's mission types land. Values the design doc doesn't fix are "Proposed:".

#### Added

- **Hits land on the body's real shape** (`scripts/combat/wounds/body_volume.gd`). A
  hitbox box is now only the first test: the round is marched through that part's 0.5 cm
  voxels (the character model, in the rest pose), so a round between the legs or past a
  wrist that only crosses the box flies on, and one that hits enters where the body starts.
  The wound channel runs as far as the body does along the round (a forearm short, a chest
  the whole trunk) instead of to the edge of the box. Built once when hosting (about 0.7 s).
- **Wounds show where they are.** Each wound keeps the rest-pose point a round went in at
  ("at") and, when it went through, came out at ("out"), replicated with the wound list (to
  half a centimetre). `WoundMarks` (`scripts/player/wound_marks.gd`) draws an entry hole and a
  bigger exit hole on the bone of the part that was hit, and a dressing once it's treated.
  The marks follow `Vitals.changed`, so they appear within `NET_INTERVAL_S` (0.5 s) of the hit.
- **Voxel blood.** Holes have a dark core and a torn red rim (ragged at an exit). While a
  wound bleeds (its replicated rate; internal bleeding stays inside, a tourniquet slows it,
  treatment stops it), blood soaks out round it and runs down the skin with gravity in 1 cm
  voxels laid on the body shape (`BodyVolume.surface`), drips off the lowest point and
  pools on the ground, spreading out as drops land. A round that goes through throws a spray
  out of the exit onto the ground behind. Treated, the stain dries dark and a dressing wraps
  the limb (a pad on the trunk or head). Cosmetic and local: no extra network traffic. One
  MultiMesh per bone, and one each for drips and the pool. The pool spills outward from
  where the first drip landed, so it shows past a body lying in it; spatter leaves specks.
- **Body types for hit shapes and blood.** `BodyVolume` keeps a shape per body type
  (`body_of` reads `CharacterModel.body`; `model_of` names the female parts "<part>_f"), so
  hits and blood follow the female body from the `art/female-model` side project once it
  merges. Male only until then.
- **World scale.** A contract zone is a seeded 2-4 km2 terrain (rolling hills, haze, distant
  terrain at lower detail) with hand-built voxel modules placed on it: the compound, small
  outposts (HESCO ring, concrete bunker, wooden watchtower), a village block of four houses in
  mixed materials, and a road checkpoint. Modules load as full 10 cm voxels within 260 m and
  unload past 340 m; a stand-in shows them up to 2.5 km away. Each has its own loot, a hostile
  garrison in buddy pairs, voxel edits and bodies, all saved with the zone. Shooting, armor,
  frags, first aid and looting work inside modules. AI navigation bakes in the background
  around players and soldiers in a fight. Main menu: **Host test zone (2 km, world scale)**,
  or `--zone [id]`.
- **Contracts and economy.** A seeded contract board (always one low-risk job; fixers'
  special jobs at enough reputation), contract zones and hot zones, a 1-5 difficulty rating
  that can understate the threat (more often with poor intel), MW5-style negotiation of pay,
  salvage share, support budget and advance (30%, kept on failure), renegotiate or abort once
  the real threat shows, up to 4 contracts held, lapsed contracts cost reputation. Cash with
  a ledger, per-faction reputation (numbers only until wave 6), a campaign clock in days with
  weekly wages and upkeep, and a safety-floor loan. Objectives (clear an area, carry an item
  out, deliver an HVT, destroy a cache) shown in the HUD. A debrief: pay and bonuses, civilian
  fines (the 8th casualty voids the contracts), MW5-style salvage picks, what was carried out
  (MOLLE pouches and their contents counted), casualties, reputation, intel turned in or sold.
  A shop for gear, repairs, medical supplies and support calls. Main menu: **Contract board
  (offline)**.
- **People.** Civilians who go about their routines, flee and hide from gunfire and never
  fight; casualties caused by the squad count against the contract, others don't, and AI
  won't shoot through a civilian. Hostile HVTs try to expose the squad and run until
  zip-cuffed; friendly HVTs follow; captives can be led, stopped, sent to cover, searched and
  carried (the waist body point). Intel (laptop, phone, documents) on officers and at sites,
  counted once carried out; enemy positions reported by radio bank at once. Badly hurt,
  isolated hostiles may surrender. A main menu checkbox puts people in the compound.
- **Base hub and roster.** A walkable FOB with an armory (the company stash; carriers keep
  their MOLLE pouches and contents), a motor pool (for wave 5), a medbay, a hiring board and a
  shop terminal. Squadmates are persistent people: name, role, skills (aim, nerve, medical,
  movement) that grow with experience along with their wage, their own gear, history and
  injuries (broken bones, burns, blast lung, heavy blood loss mean days out; the medbay
  shortens it for money). A rotating hiring pool; no fixed starting squad. Prep before a
  deployment: kit up, assign squadmates and roles, buy supplies, deploy. An AI squadmate left
  behind alive goes MIA; the respawn pool is 4 free in a contract zone, 8 in a hot zone, then
  bought. Main menu: **Campaign: host at the base (FOB)**; Join follows the host there.
- **Map, briefing, extraction.** **M** opens a map with an Arma-style grid and references,
  zoom and pan, your squad's positions, shared markers and lines, intel enemy positions,
  objectives and extraction points (every player and late joiner sees them). A briefing on
  the map before a deployment: contract, objectives, known enemies, plan marks, insertion
  point, supports (a list until wave 5), ready-up. Extraction at a landing zone, a grid
  reference or a purple smoke, once every living player and the AI you bring are inside, the
  host confirms and a 10 s countdown runs; it reports who and what got out. A reinforcement
  timer sends hostile waves from beyond the map edge, sooner and bigger over time, with no
  on-screen timer. Main menu: **Play the test contract (briefing, extraction)**.
- `Campaign`, `Economy`, `Contracts` and `People` autoloads; one save per campaign.
- Tests: world, contracts, people, base and map suites (20 in all, all in CI).

#### Fixed

- One join handshake for every kind of level: a client joining a hosted zone, a campaign at
  the base or a deployment now loads the host's level before anything replicates.
- A joining client's player starts at the gate or insertion point instead of the middle of the
  level, and loading magazines right after joining no longer stops with "you moved".
### Scavenging review fixes

#### Fixed

- **An AI that picks up a rifle from a body now fights with it.** Unequipping his own dry
  rifle switched him to his sidearm, and nothing switched him back: a marksman kept firing
  9mm with a loaded MK18 on his back.
- **Medical restock counts the whole basic load.** A tourniquet in the holder and one in the
  IFAK are a basic load of two. Each was compared on its own against everything he carried,
  so a rifleman down to one tourniquet wanted none.
- **A dry M4 takes the body's 5.56 magazines, even part-used ones, instead of the MK18**, as
  the scavenging rules say. Part-used magazines scored lower than the rifle swap.
- **A stowed pouch or carrier takes the room its contents fill.** Only the empty pouch or
  carrier counted, so a full sustainment pouch (2 L) went into a pack as 1 L, and a carrier
  with every pouch loaded as a bare 8 L. An empty pouch still folds down to its own size.
- **The medium carrier's knife no longer clips into the first mag pouch:** its point moved up
  2 cm, level with the heavy carrier's.
- **The IFAK and radio pouches are no longer inside the upper arm.** Their side points on the
  medium and heavy carriers moved 13 cm rearward, clear of the arm, the slung rifle and the
  pack. With the arms hanging (downed, dead, unarmed, the inventory preview) the arm used to
  hide the IFAK completely.
- **A looter who goes down lets go of the body.** A squadmate sent to carry that body waited
  beside it for good.
- **An AI can't get stuck walking to a body.** With a player standing still between them, it
  pushed into the player for good. Like a medic reaching a casualty, it now sidesteps after
  1.5 s without getting closer and leaves the body for a while after 12 s.
- **"Scavenge that body" works past 40 m from the leader.** The order went out, then was
  quietly dropped by the leash that should only hold back scavenging on his own initiative.
- **Drag and drop works in the inventory screen.** Pressing a tile rebuilt every tile, which
  freed the one under the mouse, so Godot never started the drag. A click now only restyles
  the selection.
- **A right-click menu won't act on the wrong item.** If what it was opened on moves or goes
  while it's open (a reload, loading magazines), choosing an action does nothing.
- The logistics test's breach check waits (up to 3 s) for the navigation map to take the
  rebaked chunks, instead of a fixed 3 frames that a slower machine (CI) can miss.
- The scavenge tests now check that a looter lets go of the body, with two squadmates
  wanting the same body, and that the leash spares an order.

#### Changed

- **Grenade and binocular pouches go on the chest, where they can be seen.** The medium
  carrier has two new Chest points on the upper front; grenade and binocular pouches take them
  first, a grenade pouch then a free mag point. Every back point sits inside the pack, so the
  grenadier's grenades and the team leader's and marksman's binoculars were hidden. GP and
  sustainment pouches stay on the back.

### Wave 4 groundwork and a spall pain fix (cghath, 2026-10-11)

#### Added

- `Campaign` autoload (`autoload/campaign.gd`): the host-owned campaign save
  (`user://saves/campaign_01.json`) that the wave 4 mission loop keeps its money, contracts
  and roster in, one section per part. `CompoundLevel.map_area()` gives the map its playable
  area. Nothing uses either yet, so play is unchanged.

#### Fixed

- Spall from a steel plate stop now counts its pain inside the plate stops' capped budget
  (`PLATE_IMPACT_MAX`) instead of on top of it, so plate hits alone, spall included, never
  knock a healthy soldier out. Six 5.56 plate stops at 50 m plus two face spall wounds could
  reach 0.88 pain and drop someone (armor suite, "6 plate hits" check).

### AI scavenging, visible tourniquets and IFAKs, and looting MOLLE pouches (Captain, 2026-10-11)

#### Added

- **AI scavenging.** Out of contact, an AI soldier short of something goes through a nearby
  dead body and takes what it needs, one item at a time, each pick taking its time (a pouch
  1.5 s, a pack 4 s, a plate swap 8 s). Squadmates and enemies follow the same rules
  (`scripts/ai/scavenge.gd`):
  - **Ammunition first:** only magazines his own weapon takes, up to his role kit's basic
    load. A marksman leaves 5.56 magazines alone.
  - **Medical items** his kit lacks, counting what's left in his IFAK. Tourniquets, gauze,
    chest seals and bandages come before the rest, and a loose item before a whole kit.
  - **Then grenades and smokes, and anything else his kit lost** (a team leader's radio).
    Intel, once it exists, always comes.
  - **Armor only well out of contact:** a plate that clearly protects more than his own (his
    is cracked through or rated lower) and fits his carrier, or a helmet. His old piece stays
    on the body.
  - **Another rifle only when his own has no rounds left anywhere** and the body's has some.
    A dry M4 takes the MK18's magazines instead, since they fit.
  - **Never past 35 kg of load** (armor swaps and intel aside), and never bulky items, spare
    carriers or packs. The rest stays for players.
  - **One soldier per body.** A squadmate about to carry a fallen friend's body waits while
    someone cross-loads from it. A dead player's body is never touched: that gear waits for
    its player under the gear marker.
  - **Contact stops it** at once, and the item in progress stays on the body.
  - **Command menu, 6 Action:** "Scavenge that body" sends the nearest selected squadmate to
    the body under the crosshair. "Scavenge freely" and "Don't scavenge" switch it on or off.
  - The HUD shows "Going to the body" and "Searching the body", and he calls out "Checking
    the body".
- **Tourniquet holder** (`pouch_tq`): an open-top MOLLE holder for one tourniquet, on a new
  Tourniquet point on every carrier, on the front mag row on the support-hand side. Every
  role's base kit now carries one with a tourniquet in it, on top of the one in the IFAK
  (one on the kit, one in the kit). You can see the tourniquet in it (black band, windlass
  across the top, red tab).
- A full IFAK pouch shows its red pull tabs.
- A new scavenge test suite (31 checks), run by `tools/run_tests.sh`.
- **CI:** GitHub Actions runs all fifteen suites on every push and pull request, one job per
  suite, on the Linux editor of the Voxel Tools v1.7 release (`.github/workflows/tests.yml`).

#### Changed

- The IFAK pouch's Medical point moved from the back of the medium and heavy carriers, where
  the pack hid it, to the right side. The utility pouch that was there went to the back. On
  the medium and heavy carriers the knife moved up to the chest to make room for the
  tourniquet.
- A pouch that names an item (the tourniquet holder for a tourniquet) is filled before one
  that takes the item's whole type (the IFAK pouch).

#### Fixed

- **Looting bodies with MOLLE pouches:** the Loot list now shows what's on the carrier and
  in its pouches, and you can take those one by one. Before, magazines in pouches weren't
  listed at all. Loot all hands a carrier over with its pouches empty and their contents as
  separate items, so the magazines land in your own pouches instead of being buried in a
  spare carrier in your pack.

### Captain's wave 3 playtest fix: letting go of a body

#### Fixed

- **No way to release a body you were dragging** (it only showed on self-interaction):
  Left Ctrl on the body you're dragging or carrying now shows its point with Release (or
  Put down) first, and **G** lets go of it too, since your hands are full and there's
  nothing to throw. Release also stays on your own waist point (Left Ctrl + Left Alt).

### Wave 3, part 6: medical technique animations

#### Added

- Every treatment has its own hand technique, on the action-animation system, for every
  peer, on someone else and, where allowed, on yourself:
  - **Bandages and burn dressings** wrap round the limb (ACE-style pressure wrapping) while
    the other hand holds the end.
  - **Gauze** is packed in while the other hand presses beside it.
  - **Tourniquets** go on high and tight (12 cm above the wound, towards the trunk): strap
    round, windlass turns, then into the clip.
  - **Splints** are worked along the limb.
  - **Chest seals** have their backing peeled, then go on and are smoothed out.
  - **The decompression needle** goes in slowly at the second intercostal space.
  - **Injectors** (morphine, epinephrine, atropine, adenosine) are wound up, jabbed home and
    held.
  - **IVs**, in an arm or a leg, go in along the vein with the skin stretched, then are
    taped. The **IO** is pressed hard into the sternum.
  - **CPR** is compressions 5 cm deep at about 110 a minute, hands stacked. The
    **defibrillator** gets its pads on, then hands come off clear for the shock.
  - **The surgery kit** is fine two-handed work.
  - **Bags** are held up high with a hand at the line.
  - **Blankets** are swept and tucked round the body, and **the NPA** goes in the nostril
    with the head tilted.

### Wave 3, part 5: body interaction points

#### Changed

- **ACE3-style body points.** Looking at a squadmate (down or standing) with Left Ctrl now
  shows points on their head, chest, left and right arm and left and right leg. They sit on
  the body's hitboxes, so they follow it standing or lying down. Each point offers a check
  of that part, then the treatments that go there: a tourniquet on the leg it's for, the
  NPA on the head, the IO, seals, needle, CPR and the defibrillator on the chest. A general
  point at the waist has carry, drag, give item and check condition. Self-interaction
  (Left Ctrl + Left Alt) lays the same points out like a body around the screen centre,
  with check wounds and the rest at the waist. Enemies, the dead, dummies and items keep a
  single point.
- **IVs in the legs:** an IV can go in either forearm or either lower leg, offered on that
  limb's point, but never below a tourniquet. The AI still picks the first free site,
  left forearm first.
- Checking a body part reads only its wounds, tourniquets and line, plus the airway on the
  head and breathing and pulse on the chest (with a pulse oximeter, the SpO2 and pulse).

### Wave 3, part 4: surgery kits and the other damage

#### Added

- **Surgery kits** with 2, 3 or 5 uses (common, uncommon, rare). One use is a hemostat
  clamp (about 20 s, players and medics only). It is the only fix for internal bleeding
  from the torso arteries and veins, and it also works on junctional and arterial bleeds.
  It can close a chest wound in place of a seal, but a closed chest wound has a 10% chance
  to reopen each time the casualty sprints, jumps or sets off under an extreme load, which
  brings back the open wound and its tension risk.
- **Blast overpressure** within 5 m of a frag (10 m indoors): ears ringing for 20 to 60 s,
  a concussion check, and some bruising. Within 3 m (6 m indoors) there's a chance of
  **blast lung** (toned down on Captain's call, 2026-10-11, so it's never a death timer you
  can't answer). It takes some SpO2 and stamina, then holds steady while the casualty
  rests. Sprinting, jumping, an extreme load or IV fluid the body doesn't need make it
  worse, and the strain eases off over about 20 minutes of rest. Exertion can also
  collapse a lung, a closed tension pneumothorax that the decompression needle fixes.
  Within 2 m the blast also burns.
- **Falls:** nothing under 3 m. From 3 to 6 m, leg pain and a 30 to 70% chance of a broken
  leg. Above 6 m the fall is more and more likely to be fatal (90% from 10 m).
- **Burns:** pain by the share of the body burned. Over 20% they also lose fluid like
  bleeding, which IV fluids replace. **Burn dressings** (5 s) take some pain off, one per
  10% of the body burned.
- **Hypothermia:** 30% or more blood lost and lying still for 5 minutes makes bleeding 25%
  faster. A **hypothermia blanket** (5 s) stops it, and medics put one on after the bags.
- **Deafness:** blasts, flashbangs (3 to 6 s) and sustained gunfire indoors (30 s, after
  about ten shots close by) muffle hearing through a low-pass on the sound bus, with an
  "Ears ringing" note. **Electronic ear protection** (carried) stops flashbang and gunfire
  deafness and halves a blast's.
- Checking someone shows "Coughing blood" (blast lung), "Shivering, skin cold", "Burns over
  about N% of the body" and, on yourself, "Ears ringing". Clamped and surgically closed
  wounds say so.
- The medic's kit adds a 3-use surgery kit, two burn dressings and a blanket. The gate loot
  has a 2-use and a 5-use surgery kit, burn dressings, blankets and ear protection.

#### Fixed

- The interaction test waited 3 process frames for the host's carry update, which runs in
  the physics step, so it sometimes failed on a fast machine. It now waits physics frames.

### Wave 3, part 3: heart rate, drugs, CPR and the defibrillator

#### Added

- **Heart rate** (hidden, like SpO2). It sits at 75 bpm at rest. Blood loss and pain speed
  it up, and morphine and very low SpO2 slow it. It sinks toward 40 bpm as blood loss nears
  50%, and it's 0 in cardiac arrest. Racing over 200 bpm or slower than 35 bpm for a minute
  stops the heart. Checking someone shows "Pulse racing", "Pulse fast and weak", "Pulse slow"
  or "No pulse", and a pulse oximeter now also shows the pulse.
- **Epinephrine** (medic, 2 s): +30 bpm per dose, wearing off over a few minutes. In
  cardiac arrest it raises the chance that CPR and shocks restart the heart. It keeps its
  wake-up roll: given to someone kept out only by a concussion knockout (or already coming
  round), there's a 50% chance they come round in 2 s. It can't wake anyone while blood
  loss, low SpO2, pain, trauma or arrest still holds them. There's no revive.
- **Atropine** (2 s): raises a slow heart rate, for example after a morphine overdose.
  **Adenosine** (2 s): slows a racing one, for example after too much epinephrine.
- **CPR** (a 10 s cycle, no item needed) and the **defibrillator** (a 5 s shock; not used
  up) restart a heart in cardiac arrest only once blood is back above 60%. Until then
  they do nothing, so the line and bags come first. Each CPR cycle restarts it 8% of the
  time and each shock 35%, plus 15% with epinephrine in the blood. Among the AI only
  medics do CPR and shocks; players can always do them.
- Treat menus and AI medics follow the order: line and bags, epinephrine, shocks, CPR, then
  adenosine or atropine for a heart rate out of range. A medic keeps doing CPR and shocks
  for as long as the 10-minute window lasts.
- The medic's kit adds three epinephrine, two atropine, two adenosine and a defibrillator.
  The gate loot has two epinephrine, one of each of the other two drugs and a defibrillator.

### Wave 3, part 2: breathing, the decompression needle and the pulse oximeter

#### Added

- **Per-lung breathing.** Each lung has an efficiency from 0 to 1, lowered by collapse
  (pneumothorax) and by blood in it (hemothorax). SpO2 now follows the two lungs, blood
  loss and morphine, instead of fixed amounts per chest wound.
  - An unsealed chest wound lets its lung collapse 40% over about 12 s. Once it's sealed
    the lung re-expands over 2 minutes.
  - While a chest wound bleeds, the blood fills that side's lung, and it stays there:
    there's no chest drain in the field, so seal chest wounds early.
  - A tension pneumothorax collapses its lung fully and squeezes the other one (40% off).
- **Decompression needle** (medic, 5 s): relieves a tension pneumothorax at once, so the
  cardiac arrest it was heading for doesn't happen. Treat menus and AI medics use it right
  after the airway, before chest seals.
- **Breathing rate** (hidden): faster as the lungs fail or blood is lost, slower on too
  much morphine. Checking someone now shows "Breathing fast" or "Breathing slow", "No breath
  sounds on the left/right" for a collapsed lung, and "Trachea shifted, neck veins bulging"
  for a tension pneumothorax.
- **Pulse oximeter:** carry one and Check condition (and Check wounds on yourself) reads
  the SpO2, or "no reading" in cardiac arrest.
- The medic's kit adds two needles, a pulse oximeter and a second IO kit. The gate loot has
  two needles and an oximeter.
- AI medics keep trying for a line up to 4 times (a missed IV uses a catheter) before
  leaving it to someone else.

### Wave 3, part 1: IV and IO lines, fluids, pressure bags

#### Added

- **IV catheters** in 10, 12, 14, 16, 18 and 20 gauge. Bigger bores run fluid in faster
  (5x down to 0.6x the 18 gauge), take longer to place (22 s down to 8 s), hurt more and are
  rarer. An IV goes in the left forearm (the right if the left arm has a tourniquet).
- **IO kit:** a sternal line in 5 s that always works, at the 18 gauge rate.
- **Saline and blood bags** of 250, 500 and 1000 mL. They work the same; one bag runs at a
  time and takes about 2.75, 4.5 or 7.5 minutes through an 18 gauge.
- **Pressure bag:** doubles the flow of an IV with good veins or an IO. From 37% blood lost
  the veins collapse: an IV then runs at half its rate, or 1.25x under a pressure bag.
- **IVs in shock:** from 25% lost an IV takes longer to place (up to twice as long) and can
  miss (up to 60% of the time at 50% lost), which uses up the catheter. In deep shock and
  cardiac arrest, IO is the better pick.
- Treat menus list a line from 15% blood lost, then a bag, then a pressure bag once veins
  collapse, with one entry for each kind you carry. You can't put a line in yourself, but
  you can hang a bag on your own line. Checking someone shows their line and bag.
- AI medics put a line in (IO first when veins have collapsed), hang a bag and add a
  pressure bag after bleeding control and before splints. A squadmate without the items
  calls the medic for them.
- The medic's kit adds three 18 gauge and one 14 gauge IVs, an IO kit, two 500 mL saline
  bags, a 500 mL blood bag and a pressure bag. The gate loot has IVs (one rare 10 gauge),
  an IO kit, saline, a 1000 mL blood bag and a pressure bag.

#### Removed

- **Slow blood recovery** (the stand-in until IV): blood no longer comes back on its own.
  A casualty past 40% lost stays out until fluids bring them back under it.

### Captain's wave 2 playtest asks

#### Added

- **Inventory screen, Star Citizen style:** Tab opens a full-screen personal inventory. A
  live 3D preview of your soldier and his kit sits in the middle (drag him to turn him), with
  the equipment slots (helmet, carrier, backpack, plates, primary, sidearm) down both sides.
  Containers are on the left as grids of item tiles (carrier pouches, vest, pockets,
  backpack, hands, and what's on the ground within reach); the selected item's details and
  actions are on the right. Every tile shows a preview image rendered at runtime from the
  item's own voxel model (cached per item; a coloured tile where nothing renders) with its
  name and a mass, count or condition readout.
  - Drag tiles between containers, pouches and slots; onto the soldier to equip or attach;
    onto the ground panel to drop; from the ground panel to pick up. Right-click a tile for
    its actions (equip, attach, stow, use, load magazines, move, drop), double-click for the
    first. Load magazines also has a button at the top of the containers when you have
    loose rounds to load. Everything still goes through the host's requests.
- **MOLLE attachments:** carriers have typed attach points (light 6, medium 9, heavy 12:
  mag, pistol mag, knife, radio, medical and utility). New attachables: single and double
  M4 mag pouches, double pistol mag pouch, radio pouch (and an AN/PRC-152 radio), binocular
  pouch (and binoculars), GP utility pouch, sustainment pouch, IFAK pouch, grenade pouch and
  a fixed-blade knife, all with mass. Pouches hold their contents (a double mag pouch two
  rifle magazines, an IFAK pouch medical items, a sustainment pouch anything small).
  - The MOLLE view (click the carrier twice, or the MOLLE button) closes in on the carrier
    and lays its attach points down the sides with lines to where they sit; drag compatible
    items onto them, or drag an attached pouch to another point.
  - Attachments stay on the carrier: dropping, picking up, looting or stowing a vest keeps
    its pouches and what's in them, and they're saved with the zone and replicate.
  - Reloads take magazines from mag pouches first; magazines, grenades and medical items you
    pick up go into the pouches made for them first. Pouches and their contents count in
    your mass. Attached pouches show on the soldier as small boxes on the carrier.
  - Role kits put three double mag pouches and an IFAK pouch on every carrier; the team
    leader adds a radio and binoculars, the medic a sustainment pouch and a knife, the
    grenadier grenade pouches, the marksman a pistol mag pouch and binoculars, the
    autorifleman and rifleman a GP pouch (and the rifleman a knife). Pouches lie in the
    compound loot west of the gate.
- Tests: MOLLE rules (points, pouch capacity, reload from pouches, detach and re-attach,
  mass, save round trip) and MOLLE through the host and the inventory screen (attach,
  move, detach, drag and drop, drop and pick up a carrier with pouches) in the logistics
  suite.

#### Changed

- Moving a stack into a container that can't take all of it moves as many as fit.
- Dropped items saved with the zone come back with whole numbers and item ids restored
  (like bodies already did).

### Captain's wave 2 playtest fixes

From Captain's playtest of the wave 1 build. The Star Citizen-style inventory and MOLLE vest
attachments Captain asked for at the same time are under "Captain's wave 2 playtest asks" above.

#### Changed

- **Plate and helmet wear:** every hit, stopped or not, now wears a plate or helmet down by
  round class and the piece's durability, and the HUD shows that integrity (it used to show
  only the share of voxels knocked out, so a heavily dented plate still read 94%). A 5.56 round
  takes about a quarter of a light PE plate (worn out in 4 hits), 18% of a heavy ceramic plate
  (6) and 8% of a medium steel plate (13). Helmets: bump 30%, medium 23%, heavy 18% per hit.
  Below 30% a steel, PE or composite piece starts letting rounds through, and at zero it stops
  nothing ("worn out"; ceramic still shatters).
- **Plate-stop pain:** a burst into the plates hurts. Each stop adds more impact (pistol 0.05,
  5.56 0.12, 7.62 0.22), up to 0.7, which was 0.35. Six 5.56 stops in a row reach the cap.
  That plus a cracked rib stays just under the knockout threshold at full blood, so plates
  alone still never knock out a healthy soldier, but a wounded one who has lost blood can go
  down.
- **Bullet holes in wood and sheet metal** are now the size of the round: a dark core the
  bullet's diameter (5.7 mm for 5.56, 7.8 mm for 7.62, 9 mm for 9 mm) in a splintered or
  bare-metal rim, going in and coming out (bigger on the way out of wood), instead of a whole
  10 cm voxel knocked out. A voxel breaks out only after 10 rounds through it (16 for sheet
  metal). Every peer sees them, late joiners too, and they're saved with the zone. Old saves'
  whole-voxel holes still load.
- **Knees:** legs bend at the knee. Crouching and kneeling put the feet under the hips, with
  the back knee down on the ground, and knees fold as the legs swing through when walking.
  Shin hitboxes follow the shins.
- **Dragging, Arma-style:** you face the casualty and crouch over them, and the view goes
  down with you. You back away with S (strafing works, W doesn't walk onto them), and the
  camera turns round with you when you take hold or let go. Looking at the body you drag (or
  carry) offers **Release** (or Put down) in the Ctrl menu, as well as in the Ctrl+Alt menu.

#### Fixed

- Looking far up or down could tip the view past vertical, swing it round about 90 degrees
  and leave you facing backwards, with mouse look or movement inverted. The cause was leaning
  (and the stance tilt) leaking into the view's turn on every mouse move. The view now stops
  at about 83 degrees up or down and can't turn away from the body.
- AI squadmates keep the older, looser momentum. The player's tighter grip from the movement
  fix left them stuck on door frames.

### Captain's wave 1 playtest fixes

All five fixes, each built, reviewed and fixed by its own agent. The movement fix (sliding
as if on ice) came last, on `fix2/p2-movement`.

#### Changed

- **Movement feel:** no more sliding on ice. Stopping now takes about 0.2 s from a jog or a
  sprint (0.4 m from a jog, under 0.9 m from a sprint; was 0.6 m and about 1.6 m), and
  after a turn, or when the view swings round mid-run, the old heading is shed in 0.1 s
  (about 0.2 m of drift on a 90 degree turn) while the new direction builds up over the
  usual 0.3 s. Gentle turns keep their pace. A full load still doubles all of it.

- **Knockouts:** getting hit in the plates no longer knocks you out. Stopped rounds bruise
  (plate impact pain about halved and capped at 0.35 however many land), still stagger you,
  and 7.62 still winds you. A medium-armor soldier hit 2-3 times, or 6 times in a burst,
  stays conscious and fighting.
  - Pain knocks you out only when it stays at the threshold for 3 seconds, not on a brief
    spike. One rifle round through a limb hurts (pain 0.45-0.65, was 0.6-0.9) and often
    breaks the bone, but doesn't knock a healthy soldier out. Pistol wounds 0.25-0.4.
  - Steel spall is rare and minor: 5% of pistol, 10% of 5.56/7.62x39 and 20% of full-power
    stops, one wound at most, usually a scratch. It used to be 1-2 wounds on every stop.
  - Cracked ribs from plate stops are rarer and depend on range (5.56: 20% point blank,
    none past 100 m).
  - Two .308 helmet stops no longer knock you out on their own; it takes three, or the
    concussion roll.
- **Armor voxels:** plates and helmets are one voxel thicker (PE and ceramic plates 3 cm,
  steel and side plates 2 cm, helmets 2-3 cm). A stopped round leaves a small dent of a few
  voxels and never a hole; only a round that gets through makes one. Repeated hits on one
  spot wear through: about 5 for steel, 3 for polyethylene and helmets.
- **World materials:** wood and thin sheet metal can be shot through, hitting whoever is
  behind with less energy (a thick stack of wood stops it). Concrete stops every small-arms
  round with no hole and takes a small 5 cm crack mark instead, seen by every player, for
  late joiners too, and saved with the zone. Frags chip concrete and blow holes in planks
  and sheet metal. The compound now has concrete, sandbags, wooden crates, a wooden shed
  with a sheet-metal roof and a shipping container. AI prefers concrete and sandbag cover.
- **Animations:** fireman's carry (the casualty limp over your shoulders), drag (backing
  away in a crouch holding the carrier straps, casualty on their back head first), pick up,
  equip, stow and drop (hand to the slot), weapon draw, treating (kneeling, hands at the
  wound) and looting. Every player sees them, including late joiners, and hit areas follow
  the poses. In first person the view model drops out of the way. You can't fire while
  dragging.

#### Fixed

- Plates, helmets and armor lying on the ground take damage: they dent, crack and lose
  integrity like worn armor, and keep it when picked up.
- Plates (especially thin steel ones) that landed face first could sink into the ground or
  crates and couldn't be picked up.
- The smoke suite's random "plate protected the body" failure.
- Tests: new materials and animations suites (14 suites by default).

### Wave 2 of the build plan (phase 3 finish)

Built by three agents in parallel (kit and treatment, AI casualty care, ammo and smokes),
then finished by two more after Captain's direction mid-wave: no revive, bodies keep their
gear, medics put the wounded first. Merged on `dev`. See `docs/build_plan.md`.

#### Added

- **Field kit on the wound model:**
  - The IFAK and trauma kit are bags of real items. IFAK: 1 tourniquet, 2 pressure
    bandages, 1 hemostatic gauze, 1 vented chest seal. Trauma kit: 2 tourniquets, 4
    bandages, 2 gauze, 2 seals, 1 splint, 2 morphine, 1 NPA. Loose items are used first,
    and the inventory screen shows what's left in each kit.
  - Treat yourself (Left Ctrl + Left Alt) or others (Left Ctrl): a Treat submenu lists
    what's needed in casualty-care order with the body part ("Tourniquet, left thigh"),
    greyed out with a reason when you don't carry the item. H applies the next item for
    your own most urgent wound.
  - Times: tourniquet 4 s (6 s on yourself), bandage 5 s, gauze 8 s, chest seal 5 s, splint
    8 s, morphine 2 s, NPA 3 s. Moving away, going down, or the casualty being moved
    interrupts it without using the item.
  - Tourniquet: stops all bleeding on that limb below it and adds pain; on a leg you limp.
    A rushed one (1.5 s, or any put on under fire) only stops 70%; a second beside it fixes
    that. Packing the wound with gauze lets you take it off again.
  - Bandages fix venous, muscle and graze wounds; gauze packs junctional bleeds. A vented
    chest seal stops tension pneumothorax from starting (it can't relieve one already
    started). A splint lets you jog on a broken leg and steadies a broken arm.
  - An unconscious casualty's airway can block; an NPA prevents or clears it. A short
    spell out (under 45 s) clears its own airway.
- **Consciousness follows the body (no dice):** you stay out while any cause holds: low
  blood oxygen (SpO2 under 85), pain at the knockout threshold, 40% of your blood lost,
  cardiac arrest, a concussion, morphine sedation, or too many serious wounds at once
  (total trauma). About 10 to 20 s after the last cause clears you come round on your own.
  - **SpO2** (hidden): falls with heavy blood loss, an unsealed chest wound, tension
    pneumothorax, a blocked airway and too much morphine. Your vision greys and closes in;
    a medic checking you sees laboured breathing and blue lips. About 2 minutes under 70%
    stops the heart.
  - **Morphine** is a level in the blood: a dose goes in over 30 s and halves every 12
    minutes, and pain relief follows the level. Two doses are fine, three sedate, five or
    more slow breathing dangerously.
  - **Slow blood recovery** (Captain's stand-in until IV in wave 3): once every bleed has
    stopped, internal ones too, the body makes back 1.5% of its blood a minute, so a
    patched-up casualty past 40% lost comes round after a few minutes. Any bleeding stops it.
  - Check condition shows plain signs: Unresponsive, Breathing laboured, Blue lips,
    Pinpoint pupils (morphine).
- **AI casualty care:** the fire team's medic answers first, then the battle buddy, then
  the other medic ("Moving to Charlie", "Treating Charlie"). Medics put the wounded first
  even in a firefight: smoke between a casualty in the open and the threat, drag to cover,
  massive bleeding first, the rest once in cover; they fight back only at close range, and
  the rest of the squad covers them. Afterwards they stay with an unconscious casualty or
  carry them with the squad until they wake. A wounded squadmate puts its own tourniquet on
  at once and calls "Medic!" for what it can't fix. A responder that can't reach a casualty
  sidesteps and then hands them to someone else.
- **Bodies keep their gear:** every dead player, squadmate and enemy leaves a body where they
  fell with everything still on it; only something carried in both hands drops. Left Ctrl on
  a body: Loot (take one thing), Loot all (what fits; the rest stays on the body), Carry,
  Drag. Bodies and their gear are saved with the zone and appear for late joiners. Past 12
  bodies the oldest goes and its gear drops where it lay.
- **Ammo:** loose 5.56, 7.62x51 and 9mm rounds; magazines weigh what they hold; empties go
  back in the pouch and stack. "Load magazines" on loose rounds (inventory screen) fills that
  calibre's magazines, fullest first, at 5 rounds a second; moving or firing stops it.
- **Coloured smoke:** green, yellow, blue and purple grenades (for the wave 5 supports);
  Shift+G cycles through what you carry. Coloured smoke blocks AI sight like white.
- Tests: medical, casualty (including a two-lap soak and an under-fire engagement) and
  logistics suites, in the default run (12 suites).

#### Changed

- You respawn with an M4, 2 spare magazines and 90 loose rounds, a smoke and a frag. Your
  body stays where you fell with your old gear, and the gear marker floats over it.
- Medics carry a trauma kit and extra tourniquets, gauze, bandages, seals, splints, morphine
  and NPAs; everyone else carries an IFAK.
- A dead squadmate leaves the squad (no slot, no orders, not on the roster) and isn't
  replaced this session.
- Squad AI routes through breached walls: once a gap is big enough to fit through, the
  navigation around it updates within a fraction of a second.
- Enemies and squadmates leave unconscious foes alone, except a dead-check within about 8 m
  while assaulting or searching a position.
- Squadmates pass through each other (no more doorway jams); AI only throws a frag when its
  arc is clear.
- The zone save keeps full number precision, so armor damage comes back exactly.

#### Removed

- **The stopgap revive.** There's no Revive anywhere: casualties come round when their body
  lets them. The 15% wake roll and the morphine overdose dice are gone too.

#### Fixed

- Dead players, squadmates and enemies no longer vanish or scatter their gear on the ground.
  Players joining or changing roles no longer delete dead squadmates' bodies.
- AI medics no longer get stuck behind a player standing on their route.

### Wave 1 of the build plan (phase 3 core)

Built by five agents in parallel and merged on `dev`. See `docs/build_plan.md`.

#### Added

- **Wound model (no more hitpoints):**
  - Hits make wounds on 14 body parts. Arteries and big veins bleed by how close the round
    passed, so a femoral hit takes about 2 to 3 minutes to knock you out.
  - Bones can break: a broken leg means no sprint and walking speed; a broken arm means
    heavy sway and slow reloads.
  - Heart hits stop the heart within seconds, lung hits open the chest (with a chance of
    tension pneumothorax), and a head hit past the helmet is fatal.
  - 6 L of blood. From 15% lost you sway more, recover stamina more slowly and move slower;
    from 30% you can't sprint; at 40% you're unconscious. At 50% the heart stops and a
    10-minute cardiac-arrest window starts.
  - Pain from 0 to 1 can knock you out, more easily the more blood you've lost. Once
    stable you have a chance to wake every 15 s.
  - Blood loss fades and greys your vision, with tunnel vision from 30% lost. Unconscious
    shows a black screen with UNCONSCIOUS or a cardiac-arrest countdown.
  - Frag grenades cause 3 to 8 fragment wounds on exposed parts; walls, other bodies,
    plates, helmets and vests stop them.
  - Target dummy labels show condition, blood %, bleed rate, pain and wound types.
- **Armor ratings:**
  - Rounds and armor share an NIJ-named ladder (IIA to IV): armor stops what it's rated
    for and nothing above it. Light and medium helmets no longer stop rifle rounds; the
    heavy helmet stops rifle rounds up to M855 and 7.62x51 ball.
  - Plates: PE III (light), steel III++ (medium), ceramic IV (heavy); names show the
    rating. Plates only fit the right carrier (PE in the light carrier; steel and ceramic
    in medium and heavy; side plates in heavy), with a message when they don't.
  - Ceramic cracks around each hit; hits near earlier cracks get through more often, and
    enough hits shatter the plate. Cracks stay with the plate and show when inspected.
  - Steel doesn't crack but throws spall at the neck, face and arms; the medium carrier
    covers the neck, the heavy one neck, face and arms.
  - Vests are aramid soft armor that stop pistol rounds and fragments where they cover you,
    even after the plate fails.
  - Stopped rounds still hit: pain, stagger, getting winded, cracked ribs at close range,
    concussions from helmet hits, and rarely a fatal helmet stop from a full-power rifle
    within about 200 m.
  - ACE3-style ballistics: rounds lose energy with range (M855 from far enough away is
    stopped by a light plate).
- **Stances and handling:**
  - X crouch and Z prone (toggles); Caps Lock + W/S steps through three standing and
    three crouching heights and prone; Caps Lock + A/D for side stances.
  - Q/E lean: hold, double-tap to stay, tap to return; leaning stops short of walls.
  - C rests the weapon on a surface for half the sway and recoil until you move.
  - F fire mode: M4 and Mk18 have semi and auto and start on semi.
  - Movement has weight: about 0.3 s to reach a jog or stop, roughly double under a heavy
    load, with momentum into turns and a moment of sway after a hard stop.
  - Sprinting uses stamina (about 15 s from full, less under load). No sprint or jump
    while crouched or prone. Prone is steadiest, then crouched.
  - Hitboxes follow the pose, so crouched and prone soldiers are lower targets.
- **Interaction menus (ACE-style):** hold Left Ctrl for action points on items, downed
  bodies and squadmates within about 3 m; hold Left Ctrl + Left Alt for yourself. Actions:
  pick up, revive, carry (55% speed), drag (35%, the body slides behind you), check
  condition, check your wounds, use medical, put down, drop held item, and give a stowed
  item to a squadmate.
- **Squad roles and fire teams:**
  - Two fire teams of four (A and B), each with a medic. Roles: team leader, medic,
    autorifleman, grenadier, marksman, rifleman, with starting kits for AI squadmates.
  - Pick your role on the main menu; AI fills the rest.
  - Command menu: Target (focus fire), Combat mode (Safe, Aware, Combat, Stealth) and Team
    (fire teams and colour teams). F1-F8 follow squad slots; Shift+F-key adds.
  - Squadmates call out subtitles: contacts with direction and distance, reloading, man
    down, frag out, smoke out, moving and covering. Voice lines play once audio exists in
    `audio/callouts/`.
  - The HUD roster shows fire team, role and colour team.
- **Tests:** new suites `wounds`, `armor`, `movement`, `interaction` and `roles`;
  `tools/run_tests.sh` runs all nine by default.

#### Changed

- E leans right; picking up and reviving moved to the Left Ctrl menu. Ctrl and C no longer
  crouch.
- IFAK and trauma kit are stopgaps until the wave 2 kit: using one stops bleeding wound by
  wound and takes off pain; reviving stops all bleeding, brings blood up to 62% and
  restarts the heart.
- The debug K key costs 24% of your blood and adds pain; two presses knock you out.
- Squadmates no longer fire through you or each other, battle buddies don't move to new
  cover at the same time, and AI aims at your chest wherever your stance puts it.
- Downed bodies get a lying-down movement capsule (they used to block as an invisible
  upright body).

#### Fixed

- `tools/run_tests.sh` exits non-zero when a suite fails.

Phase 2, inventory depth: ammo, reloading, healing, an inventory screen, and item state
that travels with the item.

### Added

- **18 new voxel materials** for the worldspaces, with fixed colours from the faction pack's material registry: mud brick, stone, limestone, basalt, tuff, coral stone, brick, cinder block, plaster, roof tile, fibre cement, corrugated iron, thatch, tarp, glass, sandbag, HESCO and dirt berm. They are colours only for now; all materials still carve the same way.
- **Squad AI (phase 3, first pass):** the player squad has 8 slots, and AI fills every slot players don't (7 squadmates for one player, 4 for four). See `docs/squad_design.md`.
  - Arma 3-style command menu: F1-F8 select squadmates by number (~ for all), then 1-9 / 0 or the mouse wheel and middle click pick orders: move (formation, move there, stop), engage (open / hold fire), status, action (throw smoke or frag at the crosshair), formation (wedge, file, line, staggered column) and a support menu (not built yet). Orders go to the selected units; the last player to give one leads.
  - Everyone is paired into battle buddies. In a fight, soldiers take cover, crouch when not shooting, get pinned by close fire, and buddies take turns moving while the other covers. Frags go to enemies hiding behind cover.
  - Downed friendlies (players too) get help, buddy first: in a fight, smoke and a drag to cover, then a revive or a guard; out of a fight, a revive, or the buddy carries them and follows the lead.
  - Hostile fire teams (two guards, two on patrol) use the same body and AI.
  - A runtime navmesh over the compound. The HUD lists each squadmate's status and health.
  - `tests/squad_test.tscn`: roster scaling, navigation, following, a buddy carrying a buddy, a firefight and flashbang stun.
- **Grenades (G to throw, Shift+G to switch type):** frag, flashbang (new item) and smoke.
  - Frag: up to 180 damage within 8 m, falling off with distance; walls shield you. It also blasts a crater in voxel walls.
  - Flashbang: whites out the screen for up to 5 s, depending on distance and whether you were looking at it. AI soldiers will be stunned.
  - Smoke: a 5 m cloud that lasts 30 s. It blocks the view, and will block AI line of sight.
  - Every peer sees the grenade fly; the host detonates it. The compound has smokes and flashbangs next to the frags.

- **Item state:** items carry state that goes wherever they go: rounds in a weapon or
  magazine, chips in a plate or helmet. It's kept while the item is worn, stowed, dropped,
  picked up by someone else, and saved with the zone.
- **Ammo:** weapons come loaded and every shot uses a round. Firing an empty weapon tells
  you to reload.
- **Reloading (R):** loads the fullest compatible magazine you carry. A part-used magazine
  goes back where the new one came from, and an empty one is discarded. Reload times are
  per weapon (pistol 1.6 s, M110 2.8 s); you can't fire while reloading. Other players see
  your left hand working the magazine.
- **Medical items (H):** IFAK (+35 HP over 4 s) and trauma kit (+70 HP over 8 s). You get
  the smallest kit that covers your injuries; using one keeps your hands busy for a moment.
- **Inventory screen (Tab):** equipped slots and container contents, with Equip, Stow,
  Use, move to another container, and Drop. Rounds loaded, part-used magazines and armor
  damage are shown on each item.
- **HUD:** ammo counter (loaded / spare rounds) and reloading and healing indicators.
- **Aiming down sights (hold RMB):** zooms to each weapon's aim FOV (M110 30°, pistol 65°),
  lines the weapon's sight up under your eye, and cuts spread to 12% of hip fire. It also
  halves recoil and slows movement.
- **Spread and recoil:**
  - Each weapon has a spread cone, which widens while moving (up to 2.5×) or in the air (2.5×) and tightens when crouched.
  - Each shot kicks the view up and slightly sideways.
  - Stats per weapon: `spread_deg`, `recoil_deg`, `ads_fov`.
- **Downed and revive:**
  - At 0 HP you go down instead of dying: you fall face down, can only crawl, can't shoot, and drop anything you're carrying in both hands.
  - You bleed out after 60 s. Another hit while down kills you. There is no giving up.
  - Teammates revive you with E: a trauma kit takes 3 s and brings you back at 50 HP; an IFAK takes 5 s and brings you back at 25 HP. The kit is used up when the revive completes.
  - Hitboxes lie down with the body, so shots land where you're lying.
  - Dead bodies lie down too. Target dummies get back up on their own after a few seconds.
- **Ground items:** the pickup prompt shows rounds and damage. Armor on the ground shows its chips.
- **Docs:** `docs/squad_design.md`, the phase 3 squad AI design (body/driver split,
  navigation, utility intents, co-op command, inventory loop, permadeath), with the decisions made.
- **Test builds:** `tools/make_build.sh <label>` leaves a playable build in
  `builds/<date>_<label>/`: a small `contractor.pck`, a `play.bat` launcher that runs it with
  the Voxel Tools Godot (no export templates needed) and a `BUILD.txt`. Builds stay local
  (`builds/` is git-ignored).
- **Debug key K** (debug builds only, which includes test builds): hurts you by 40 so going down and dying can be tested solo.
- `Inventory.strip()` empties a body's whole inventory into entries that keep their state.
- **Tests:**
  - `tests/gameplay_test.tscn`: end-to-end checks of a hosted session through the real requests a client sends.
  - `tests/net_test.tscn`: a two-process ENet host and client.
  - `tools/run_tests.sh` runs every suite.
  - The smoke test now has 88 checks. The gameplay test covers spread, aiming, going down and reviving, and a host-owned AI body driven through the same API, and the new death rules.

### Changed

- **Design authority:** `docs/contractor_handoff.md` (Captain's decisions, 2026-10-10) now
  overrides the README's locked decisions and `docs/squad_design.md`. Both were updated to
  match: 8-slot squad, wound model, minimal HUD, new death rules, new controls.
- **Player death:** you respawn in the default kit (M4, 2 spare magazines, a smoke and a
  frag). Everything you carried stays where you died, under a floating marker that clears
  once the gear is picked up. Before, you respawned with all your gear.
- **AI death is permanent:** an AI soldier that dies doesn't respawn; its gear stays where it fell.
- **Soldier split (build plan wave 0):** `scripts/actors/soldier.gd` is now three parts so
  parallel work doesn't collide: `soldier_movement.gd` (Movement node), `player_input.gd`
  (PlayerInput node: the human driver, camera, view model, HUD) and the body with its
  host-side requests. No behaviour change.
- **Wound-model interface:** everything outside `Vitals` now goes through named calls
  (`server_hit(part, hit)`, `server_impact`, `injury()`, `condition_text()`,
  `seconds_to_death()`, `speed_mult()`, `sway_mult()` and others), backed by HP until the
  wound model replaces it. Hitboxes name their body part in a `body_part` meta (was
  `damage_mult`); `Vitals.net_state` is replicated for the wound model's extra state.
  Squad reports and dummy labels show a condition instead of HP.
- **Planned keys** (README, "Decided, not built yet"): stance adjust moves to holding Caps
  Lock + WASD, interaction to holding Left Ctrl and self-interaction to holding Left Ctrl +
  Left Alt, instead of the handoff's Ctrl+WASD, Left Windows and Ctrl+Left Windows.
- **No giving up:** a downed player can only wait for a revive or bleed out. F no longer
  does anything while down (it's reserved for fire mode); `Vitals.server_give_up` is gone.
- **Minimal HUD:** no health, ammo, grenade count, load or armor readout, as in Arma with
  ACE. The squad roster shows what each squadmate is doing, without health. Weight,
  litres, rounds loaded and armor damage are on the inventory screen (Tab).
- Keys: G throws grenades (Shift+G switches type) and Alt+G drops; F-keys are the squad command menu, so saving the zone moved from F5 to Home.
- `Player` is now `Soldier` (`scenes/soldier.tscn`, `scripts/actors/soldier.gd`), the body both players and AI use. AI bodies have non-numeric names and are driven by the host.

- Armor damage is now the item's own state, not the wearer's. A dropped plate or helmet
  keeps its holes. `Vitals` now only tracks health and healing.
- `Inventory.unequip()` returns the item with its state. `take()` accepts state.
- `Vitals` gained the downed state (`downed`, `bleed_seconds`, `server_revive`), replicated to all peers.
- **Menu:**
  - The host button is now "Play (host a session)", with a note that solo play means hosting.
  - A failed join says that someone must be hosting at that address.
  - Join retries 3 times, about 2.5 s each, so a second window started with the host still connects.
  - Hosting on a busy port suggests joining instead.

### Fixed

- Armor lying on the ground no longer tries to set an empty node name.

## [0.1.0] - 2026-10-09

First playable gray-box foundation: a co-op player can loot, gear up and shoot through
voxel armor and walls in a test compound.

### Added

- **Engine setup:** Godot 4.7.2 with Voxel Tools 1.7 (custom editor build), GDScript, Jolt physics.
- **Co-op:** ENet listen server with up to 4 players. The host is authoritative over health,
  armor and inventory, and replicates them to everyone, including late joiners. Owners
  simulate their own movement. `--host` and `--join <address>` command-line shortcuts.
- **Player:** first-person controller with walk, sprint, crouch and jump. Carried weight
  slows you down, and bulky items slow you further and block sprinting and firing.
- **Inventory:**
  - Body slots for primary, sidearm, helmet, vest, backpack and four plate pockets.
  - Volume measured in litres: pockets 2 L, plus whatever the vest and backpack add.
  - Equipping and stowing happen automatically on pickup; bulky items (HVT case, supply crate) are carried in both hands.
  - Drop (G), weapon switching (1 and 2), and an inventory detail view (Tab).
- **Items:** 28 items in `data/items.json`: rifles, a DMR and a pistol; magazines; light,
  medium and heavy carriers, helmets and plates; side plates; backpacks; medical items,
  grenades, a breaching charge, salvage and objective items.
- **Placeholder data:** 3 factions with reputation tiers (`data/factions.json`) and 5
  mission objectives (`data/missions.json`).
- **Voxel structures:** destructible 10 cm voxel walls, cover and crates. Bullets carve
  holes. Damage is kept as an edit log that the host sends to joining players and saves.
- **Zone persistence:** looted items, dropped items and voxel damage are saved to `user://saves/`. Save with F5, on quit, or reset from the menu.
- **Characters:**
  - Procedural voxel soldiers built from 2 cm voxels, in four camo variants (multicam, woodland, desert, urban), plus crash-test-yellow target dummies.
  - Code-driven animation: walk and sprint cycles, breathing, and the head following where the player looks.
  - Elbows with two-bone IK put the palms on each weapon's grip points.
  - Rifles move between the sling and the hands, and the pistol between the holster and the hands.
- **Gear art:** voxel models for the plate carriers (light, medium and heavy), backpacks
  whose depth follows capacity, the three rifles and the pistol. They're worn on the body,
  shown in first person and lying on the ground.
- **Destructible voxel armor:**
  - Plates and helmets are made of 1 cm voxels.
  - Each round is traced voxel by voxel. If it meets material it's stopped and the armor chips; if it reaches a hole it carries on to whatever is behind.
  - Damage replicates to every peer and is replayed for late joiners.
- **Armor tiers:**
  - Light: low-profile carrier with a front plate pocket, bump helmet, polyethylene plate.
  - Medium: plate carrier with front and back pockets, ballistic helmet, ceramic plate.
  - Heavy: assault carrier with front, back and side pockets, a helmet with ear covers and a visor, and a steel plate.
- **Hitboxes:** separate colliders for movement, body, head (×3 damage) and armor.
- **Test compound:** perimeter wall with a gate, a building, cover, crates, starting loot, and light, medium and heavy armored target dummies.
- **HUD:** health, weight, litres used per container, armor condition, interaction prompts and an inventory detail view.
- **Tests:** a headless smoke test with 54 checks, and a screenshot tour that regenerates `screenshots/`.
- **Docs:** README with installation steps, controls, architecture and roadmap; this changelog.

### Known issues

- No ammo use or reloading yet.
- Armor damage stays with the wearer, so a dropped plate or helmet comes back undamaged.
- No inventory screen for moving items between containers. A vest or backpack can't be dropped while it has contents.
- The head hitbox doesn't tilt with the head; the helmet does.
- The voxel world has no stream, so zones are limited to `VoxelWorld.BOUNDS`. The edit log is never compacted.
- Player inventories aren't saved; only the zone's state is.

[Unreleased]: https://github.com/cghath/Contractor/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/cghath/Contractor/releases/tag/v0.1.0
