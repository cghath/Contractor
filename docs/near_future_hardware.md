# Near-future hardware: VTOL dropship and exosuits

2026-10-16 · design doc, pre-implementation. Captain, 2026-10-16: Contractor "is near future sci
fi and we havent gotten near future sci fi down yet" — this sits alongside the game's existing
real-world-grounded fidelity (ACE3/KAT medical, real ballistics, real-world-style small arms), not
in place of it. This is the first deliberate near-future content: a VTOL dropship replacing the
UH-60 Black Hawk as the main transport, and a new exosuit equipment category (light infantry and
heavy "mech-class" tiers).

Visual direction is modelled on *Call of Duty: Advanced Warfare*'s Warbird and the Goliath exo,
per Captain's own reference images, the way `scripts/actors/movement_rules.gd` is modelled on
Tarkov's inertia and beta decay's feel: Contractor learns from them, it is not a copy of either.
**"Warbird" and "Goliath" are COD:AW's trademarked names and must never appear in shipped
content** (item ids, display names, UI text, asset filenames, code identifiers) — only as
shorthand in this doc and commit messages, same as any other acknowledged-inspiration note. Every
name actually shipped is original (see Naming below).

Reference photos (Captain, relayed 2026-10-16, not committed to the repo): two of the base VTOL
(black stealth twin-ducted-rotor dropship), one paint-scheme and one clay-model reference of the
Razorback upgrade VTOL (tan/khaki quad-rotor), four of the heavy mech-class exo, eight of the
light infantry exo.

## Summary of recommendations

1. **VTOL fully replaces the Black Hawk** for player transport/resupply/extraction calls, as a
   two-tier progression: a base VTOL available from the start, and the Razorback VTOL (Captain's
   own name, cleared for shipping) as a later, bigger unlock — not two unrelated choices. The
   UH-60 data entry and model stay in the game as world content (rescue-scenario wrecks, possibly
   other factions' aircraft); only the player faction's support calls move off it.
2. **Flight model is unchanged.** Both VTOL tiers fly through the existing generic `Helicopter`
   class (J-hook landing, contour flight, cruise AGL) with new stats and new art, not new
   propulsion physics. This is the lowest-risk path and matches the reference art, which reads as
   a VTOL that still flies and lands like a helicopter.
3. **Exosuits are a new equipment slot, not a vest reskin**, and the two tiers need two different
   mechanical treatments:
   - **Light infantry exo**: worn over the existing vest/helmet/rig (per reference art), so it
     adds its own slot and modifies movement/carry numbers; armor still comes from whatever
     plates and vest are worn underneath, untouched.
   - **Heavy mech-class exo**: recommended as a worn item with a vehicle-style flat
     damage-absorption layer in front of the normal wound model, not an extension of
     `ArmorRules`' per-plate material simulation. This is the trickiest call in this doc — flagged
     for Captain's sign-off before building, with two alternatives listed.
4. **Buildable order**: base VTOL first (most self-contained, started this session) → Razorback
   VTOL (same systems, second data+art entry, unlock-gated) → light exo (reuses the human rig) →
   heavy exo (new damage layer, new movement cap, new weapon class, likely new rig work — the
   biggest lift, and the one with an open design question).

## 1. VTOL dropship

### 1.1 How the Black Hawk is wired today

Confirmed by reading the code (not guessed):

- **Flight is generic, not Black-Hawk-specific.** `scripts/supports/helicopter.gd`'s `Helicopter`
  class (`extends Vehicle`) flies any `data/vehicles.json` entry with `"kind": "helicopter"`
  through the same J-hook landing, contour-following cruise (`CRUISE_AGL_M` 12.5 m, `CRUISE_KMH`
  250) and hover/touchdown logic. `Helicopter.flies(model)` just checks the JSON `kind`. A new
  VTOL with its own data entry flies through this class **unmodified**. The only UH-60-specific
  numbers are fallback rotor-radius constants used before a model's real art provides rotor nodes
  (`scripts/supports/helicopter.gd:65-71`).
- **One hardcoded swap point for player calls**: `HeliSupports.MODEL := "uh60"`
  (`scripts/supports/heli_supports.gd:35`) is what `resupply`/`transport`/`extraction`/`medevac`/
  `cargo` all spawn. Repointing this id (or making it resolve per-tier) is the actual "replace the
  Black Hawk" lever.
- **Landing-zone clearance is UH-60-sized**: `LandingZone.ROTOR_CLEAR_M := 9.5`
  (`scripts/supports/landing_zone.gd`) is explicitly "the UH-60's main rotor is 8.2 m" plus
  margin. A VTOL with wingtip-mounted rotor pods has a different (likely wider) footprint and
  needs this parameterized per model rather than left as one constant.
- **Art is fully procedural**, not an imported asset: `scripts/art/vehicle_art.gd` builds every
  vehicle from parametric cross-sections (`Canvas.mhull`/`mloft`/`mbox`/`mskin`/`mdisc`) in code,
  meshed and cached once per model+paint scheme. `VehicleInteriors` carves the cabin and glazes
  windows the same way. A new VTOL silhouette means a new `_<model>()` function in both files,
  following the established pattern (same system already builds the AH-1Z, AAV-7, Bradley,
  Abrams, and the boxy MRAPs) — real modelling work, but no new pipeline.
- **Seats, pilot AI-only, pose and gear are entirely data-driven**: `data/vehicles.json`'s
  `seats[]` (stance, kind) and `VehicleInteriors.FLOORS` per-model floor height drive seated pose
  and weapon pose generically (`character_model.gd`/`gear_rig.gd`'s UH-60 mentions are just the
  comment crediting the bug that built this generic system, not UH-60-specific code). Pilot seats
  are always AI-flown (`Helicopter.server_enter` refuses player entry at seat index 0/1) — matches
  the existing design doc's locked decision that aircraft are AI-flown only, and matches the
  reference art (crew-served dropship, not a player-flown gunship).
- **`mission_scenario.gd`'s `WRECK_MODEL := "uh60"`** is unrelated to player transport: it's the
  `crew_rescue` objective spawning a downed Black Hawk and its crew as world content. Leave it
  pointed at `uh60` — a wrecked near-future VTOL isn't a more interesting rescue scenario than a
  wrecked Black Hawk, and repointing it would require new wreck art for no gameplay value.
- **Test impact**: `tests/heliflight_test.gd` is model-agnostic (it reads `HeliSupports.MODEL`),
  so repointing that constant exercises the new VTOL automatically. `tests/vehicles_test.gd` has
  several hardcoded `"uh60"` literals (seat-count assertions, a pilot-seat-lock test, a door-gun
  test, a chase-camera test) that will need new model-specific assertions added alongside the
  existing ones, not rewritten — the UH-60 data entry isn't going away.

### 1.2 Does the VTOL replace the Black Hawk, or sit alongside it?

Captain's own follow-up reference answers this directly, so this isn't a guess: the base VTOL
replaces the Black Hawk as the starting transport, and the Razorback VTOL is a **later unlock**
that carries more troops — a progression tier, not a second unrelated choice. Recommendation:

- `HeliSupports` resolves its spawn model per call through a small tier lookup (campaign unlock
  state), defaulting to the base VTOL once it ships, rather than a single constant. The Razorback
  becomes available once unlocked, likely for the `transport` call specifically (Captain's framing
  was about carrying more troops); resupply/extraction/medevac/cargo can stay on the base tier
  unless playtesting wants otherwise.
- Unlock mechanism: reuse the existing support-pricing path (`Economy.server_pay_support` /
  `Prices.support_price`) rather than inventing a new unlock system — e.g. a one-time campaign
  purchase or reputation gate flips a flag `HeliSupports` checks, the same shape as everything
  else the campaign gates behind money or reputation. Exact gate (cash buy vs. reputation
  milestone vs. story beat) is Captain's call; not blocking on it to start building the VTOL
  itself.
- The AH-1Z Viper attack helicopter is **out of scope** here — Captain's brief and reference
  images are about the transport role only. Leave it as the real-world-fidelity CAS asset it is
  today; a near-future gunship would be a separate, later proposal if wanted.

### 1.3 Flight model: keep it a helicopter, or change the propulsion feel?

**Recommendation: keep today's `Helicopter` flight model for both VTOL tiers.** Reasons:

- The reference art for both tiers (twin ducted rotors / quad ducted rotors, fixed landing skids,
  a cargo ramp or side door) reads as "flies and lands like a helicopter, looks like a stealth
  aircraft" — not a fixed-wing cruise-and-stall flight model. Nothing in the brief or the art asks
  for forward-flight aerodynamics, STOL/STOVL transition behaviour, or different hover physics.
  Changing the propulsion feel would be new flight-model work nobody has asked for.
  - Captain's reference does call the base VTOL "fixed-wing-capable" in its visual read, but that
    reads as a design flavor cue about the silhouette, not a request for different flight
    physics — nothing in the actual asks (capacity, LZ behaviour, combat role) needs a stall
    speed or a runway.
  - If that's ever wanted later, it's additive: `Helicopter.flies()`/`_drive_step` is the single
    override seam (`scripts/vehicles/vehicle.gd` docs this explicitly), so a future "fixed-wing
    VTOL" mode could subclass or branch there without touching the base class again.
- Reusing `Helicopter` unmodified means every existing LZ-selection, call-in, J-hook landing,
  smoke-marker and seated-passenger system keeps working with zero behaviour changes — only the
  model id, stats and art change. That's the whole reason this is the self-contained "first slice"
  of this doc's two topics.
- Tuning differences from the UH-60 (both tiers read faster and sleeker in the reference art):
  propose cruise speed up from 250 to about 300-320 km/h for the base VTOL, LOITER_KMH unchanged;
  Razorback slightly slower (bigger, heavier-lift: propose 260-280 km/h) trading speed for
  capacity, matching the "heavy-lift variant" read of its reference art. These are starting
  numbers to tune in playtests, same caveat as every other number in this doc.

### 1.4 Capacity and armament

- **Base VTOL**: propose matching the Black Hawk's 15-seat layout (2 pilots, 2 gunners, 11
  passengers) as a drop-in replacement — same squad-support math the campaign already balances
  around, changed look and speed, not changed capacity. Keep the existing crew-served door-gunner
  pattern (M240H-equivalent) rather than inventing a new mechanic for the first slice.
- **Razorback VTOL**: Captain's own framing is "carries more troops than the base transport" as
  the point of the upgrade — propose 18-20 passenger seats (bigger bay, side-door loading per the
  reference art rather than a rear ramp), keeping crew-served gunners. Its reference art also
  shows a nose-mounted weapon/sensor pod; propose treating that as a stretch goal (a fixed
  forward-firing or sensor system) for a later pass, not required for the upgrade to ship — it's
  new mechanics, not a reskin, and nothing about the brief requires it on day one.
- Neither tier needs new armor-zone work: both can reuse the existing `"class": "aircraft"`
  armour profile and `zones[]` pattern (rotor/engine/fuel/crew/cargo) from the UH-60 entry,
  resized to each hull.

### 1.5 Build sequence (VTOL)

1. `data/vehicles.json`: new model entry for the base VTOL (own id, not reusing `"uh60"`), sized
   from the reference art's proportions; same `seats[]`/`points[]` shape as the UH-60 entry.
2. `scripts/art/vehicle_art.gd` + `scripts/art/vehicle_interiors.gd`: new `_<model>()` hull and
   cabin functions. First pass: silhouette-accurate (low flat fuselage, angular faceted panels via
   zero corner-rounding sections, two wingtip rotor-pod housings, canopy, cargo ramp) rather than
   fully greebled — same "simple voxel model as a stand-in, detail later" approach the weapons
   pack used (`docs/weapons.md`), since there's no way to eyeball-iterate without screenshots this
   session (project convention: headless only, screenshots deferred).
   - The ducted rotor pods need a new art shape, not `_add_rotor`'s exposed-blade boxes: a
     shrouded housing (an `mloft` cylinder/box) with a smaller spinning disc inside, closer to
     `mdisc` geometry than a conventional rotor.
3. `scripts/supports/heli_supports.gd`: repoint the spawn model (tier-aware per 1.2, or the single
   constant as an interim step so the swap is testable before the unlock system exists).
4. `scripts/supports/landing_zone.gd`: parameterize `ROTOR_CLEAR_M` per model's actual art
   footprint instead of one hardcoded constant.
5. `tests/vehicles_test.gd` / `tests/heliflight_test.gd`: extend (don't replace) the UH-60
   assertions with the new model's seat counts and flight-path expectations.

## 2. Exosuits

### 2.1 What "wearing one" changes mechanically

Not a cosmetic skin. Per the brief, the candidates are: carry capacity/encumbrance, movement
speed, armor/damage resistance, and strength-based actions (dragging downed squadmates, breaching,
melee). The two tiers need different amounts of each, because the reference art shows two
genuinely different things wearing them:

- **Light infantry exo** (8 reference photos): worn **over** a normal human-scale soldier body —
  visible external strut/linkage frame at the shoulders, elbows, hips and knees, with the
  existing-style plate carrier and tactical rig still worn on top, normal pouches and mag
  carriers, normal-scale weapons (an in-fiction rifle, a knife), varying helmet/visor options.
  This is soldier augmentation: the same soldier, stronger and faster, not a different unit.
- **Heavy mech-class exo** (4 reference photos): a bulkier-than-human bipedal powered chassis the
  soldier is inside/piloting, not wearing over normal gear — integrated head/sensor unit (no
  separate helmet), thick hydraulic leg actuators, a bulky shoulder/back power-pack, a two-handed
  heavy weapon held low and ready, camo-patterned plating consistent with the game's existing camo
  (not a sci-fi monochrome look). Reads as a semi-autonomous heavy-weapons platform, menacing and
  industrial.

### 2.2 Light infantry exo: new slot, its own armour pads

**Superseded in part (Captain, 2026-10-16/17; built on `claude/near-future-vtol-exosuits-cont2`):**
the "armor stays exactly where it is" bullet below no longer holds. The LX-3 carries twelve Steel
III++ pads (shoulders/upper arms, forearms, thighs, shins, stomach, collarbones, upper back, spine
pack) that are real `ArmorRules` armour: `VoxelArmor` pieces on their body parts' bones, with
their chips and integrity in the frame's item state (`ExoFrame.pad_items`, `GearRig._set_exo_pads`,
`Inventory.add_armor_hit(slot, chip, changes, pad)`). They're spall-coated, and the frame's
`spall_cover` keeps spall off arms and neck. A working frame also climbs 1.3 m higher
(`ExoFrame.climb_assist_m`). It pairs with the LX-3 Visor Helmet (`helmet_lx3`: IIIA shell,
bolted-on face guard, a visor rated for fragments only). Prices: frame $45,000, helmet $6,500. A
dedicated LX-3 plate carrier is planned (Captain: "later we'll add a dedicated lx-3 plate carrier").
The original recommendation follows for the record.

Recommendation: one new `Inventory` slot (e.g. `&"exo_frame"`), separate from `vest`/`helmet`/
`plate_*`, because the reference art shows it layering with those, not replacing them.

- **Carry/movement**: give the frame an `"assisted_kg"` stat that offsets `Inventory.total_mass`
  before `MovementRules.tier_of()`/`load_speed_mult()`/`sprint_left()` evaluate it — the suit
  carries the weight, the soldier doesn't feel it, without touching the ballistics/armor-wear
  pipeline at all. This is a small, additive change: one mass-offset read at the handful of call
  sites that already read `Inventory.total_mass` for movement, not a new stat system. Concretely
  this raises the effective `BURDENED_KG`/`OVERLOADED_KG`/`CRITICAL_KG` thresholds for a wearer,
  matching "lighter augmentation, closer to normal soldier gameplay but enhanced" from the brief.
- **Strength actions** (drag speed, breach speed, melee damage): smaller, separate hooks at
  whichever specific functions currently gate those (not yet located precisely — flagged as a
  short follow-up read before implementation, not a new subsystem; expect a handful of call sites
  to multiply by a wearer check, the same shape as the mass-offset above).
- **Armor stays exactly where it is today**: a light-exo wearer's protection still comes from
  whatever vest and plates they have equipped in the normal slots, under/alongside the frame.
  `ArmorRules`, the ballistics ladder, and plate wear/cracking are untouched for this tier.
  Optional nice-to-have, not required: the frame itself could carry a trivial structural rating
  (e.g. stops `FRAGMENT` only, like exposed skin behind a vest already implicitly doesn't) — flag
  as a proposal, skip unless it's cheap once the slot exists.
- **Rig/animation impact**: low. The wearer is still human-shaped and still uses the normal
  `CharacterModel`/seated-pose/weapon-pose systems; the frame is additively modelled gear on the
  existing rig (similar in spirit to how a backpack or plate carrier already renders on the body),
  not a new skeleton.

### 2.3 Heavy mech-class exo: the trickiest compatibility question, not guessed silently

The brief is explicit that this needs a real proposal with tradeoffs flagged, not an assumption.
Three options considered:

**A. Extend `ArmorRules` to cover the whole suit as very heavy plates.** Rejected as the primary
approach: `ArmorRules` is built around per-body-part coverage (chest/abdomen/pelvis, front/back/
side) and material-specific wear (ceramic cracking, steel spall, wear-through) tuned for human-
scale vests and plates covering parts of a human hitbox. The heavy exo's reference art is a single
integrated chassis, not discrete plates over discrete body zones — forcing it through this system
either means pretending it's one enormous plate (loses the "soldier inside a platform" read) or
building a parallel per-zone coverage map for a non-human silhouette, which is most of the cost of
option B without the fit.

**B. Model it as a `Vehicle`** (full zone/HP/wreck model, player "drives" it bipedally, exits to a
normal soldier when it's destroyed). Closest fit to how the reference art actually reads (a
"semi-autonomous heavy-weapons platform" the soldier pilots), and reuses a damage model the game
already has for exactly this kind of flat zone-armour, zone-HP absorption (`Vehicle.zone_health`,
`ZONE_*` constants, armour classes). Costs: a soldier "entering" a mech is a much bigger change
than an inventory item — new entry/exit flow, new seat kind, a wreck/destroyed state distinct from
a normal casualty, and it sidesteps the squad-member wound/medical model entirely while worn
(no bleeding out in a mech, which may or may not be wanted).

**C. A worn item with a vehicle-style flat absorption layer in front of the normal wound model.**
A soldier wearing the heavy exo gets a "suit integrity" pool (reusing `Ballistics.LEVELS` for what
threat tiers it's rated against, the same ladder `ArmorRules` already uses) that absorbs hits the
suit is rated for, like an aircraft zone's `hp_kj`, before anything reaches the wearer's real
`Vitals`/`WoundModel` underneath. This was this doc's original recommendation as the practical
middle ground between A and B — **not what Captain picked; see Decided below.**

**Decided (Captain, 2026-10-16), overriding this doc's C recommendation**: closer to option A than
either C or B, but not A as written off above either. Captain's own words: "based on references
armor plates are where they are seen, well model is using our armor model so pilots can be wounded,
shot through it eventually etc and it wont be invincible. also adds worrying about the cost to
repair it train ew pilots etc." Parsed into what this means to build:

- **Real `ArmorRules` per-part plates, not an abstracted pool.** Extend the existing per-body-part
  coverage/penetration/wear-through math to the suit's own zones (torso, shoulders, limbs) instead
  of a single flat absorption number — this is what option A actually costs when it isn't taken as
  a shortcut (the "parallel per-zone coverage map for a non-human silhouette" A's writeup above
  flagged as the expensive part): mapping real coverage zones to the reference art's actual plate
  layout (torso plate, shoulder pauldrons, forearm/shin bracers — see the parts-breakdown reference,
  2.4's image set), not a renamed vehicle-zone system and not one enormous plate.
- **No invincibility.** A plate can be shot through same as any other plate carrier's: once a zone's
  coverage is defeated (cracked/worn through, `ArmorRules`' existing penetration math), the round
  reaches the wearer's real `Vitals`/`WoundModel` underneath, same mechanic as every other armor
  tier in the game — not C's separate "pool empties, then normal rules start" abstraction. This
  keeps the heavy exo inside "every mechanic serves the ACE3/KAT-grounded medical pillar" that C's
  tradeoff note above worried it would step outside of; a thicker, bigger plate is still a plate.
- **Engineering cost**: closer to what the doc estimated for option A than for C — the real work is
  the per-zone coverage map matching the suit's silhouette (torso/shoulder/limb hitboxes sized and
  placed for a non-human frame) and plausible plate ratings per zone (ceramic/steel/composite,
  thickness implying mass and threat tier), not a new damage-model layer. Replan effort for this
  tier against A's cost estimate, not C's.
- **New scope, not previously in this doc**: Captain flagged "worrying about" repair cost and pilot
  training/certification as ongoing friction for owning a heavy exo — described as a concern, not a
  confirmed spec. This needs its own concrete proposal (e.g. a repair cost scaled by damage taken
  through `Economy`/`Prices`, a training requirement gating which roster soldiers can equip it)
  flagged back to Captain before building, not guessed at here. See open question 5 below.

- **Movement**: slow and limited, not a speed buff — the reference art is "bigger, slower,
  heavily armored/armed," the opposite of the light exo. Propose a fixed speed multiplier
  (independent of carried `kg`, since the suit does the lifting) capped well below a light
  soldier's sprint — e.g. permanently at or below `MovementRules`' BURDENED multiplier (0.9),
  never reaching full sprint, trading mobility for durability and firepower.
- **Weapons**: the reference art's integrated two-handed heavy weapon implies a new weapon class
  sized beyond what a normal soldier could carry (a support-weapon platform, not a reskinned MG),
  replacing the normal primary/sidearm slots rather than coexisting with them.
- **Rig/animation**: the biggest unknown. The reference art's silhouette (hunched torso, no
  separate head, thick leg actuators) is not a human skeleton wearing gear — it likely needs its
  own `CharacterModel` variant or stand-in rig, which is real production cost beyond the damage-
  model question above. Not scoped further here; flagged as the reason this tier ships last.

**Built, first playable slice (2026-10-17, `ExoMech`, branch `claude/heavy-exo-55eabf`):** the
Atlas-pattern Walker (`exo_mech_heavy`) as the Captain decided above. What the slice is, and why:
- **Not a new skeleton (open question 4):** the suit is built round the normal `CharacterModel`
  rig, drawn 1.25x while piloted (`suit_size`: plates, hitboxes, eye and capsule all scale, about
  2.3 m tall; most doors are too low for it), so wounds, ragdolls, poses and networking keep
  working. The pilot's body and kit are hidden inside dark mechanical cores; only his head shows,
  low between the shoulders (Captain's refs, 2026-10-17).
- **Entry and exit through the back, with the manual release** (Captain, 2026-10-17, pointing at
  AW's punch-out scene): the release panel on its back unzips it, the power pack and back plates
  splitting at the spine, then the thighs' and shins' backs; the pilot is in it, arms pushed into
  the sleeves, and it zips shut. Out: it unzips and he steps back out. A downed suit lying face
  down (as in that scene) that you climb into and that pushes itself up is not built yet.
- **Plates:** fifteen `VoxelArmor` pads (`stats.pads`, reusing the LX-3's per-part pad system):
  all AR500 steel (Captain, 2026-10-17): IV on the chest, head unit, shoulders and back, steel III on the belly, steel III++ on the arms and legs
  (Captain, 2026-10-17: the chest "should be steel 3", then "some of the armor to level 4 steel"), the head unit's
  visor III. Penetration reaches the pilot's real wounds. Painted in the wearer's camo.
- **Worn, but only by climbing in:** the `exo` slot, so it travels with the soldier like any item
  (state, saves, net), but `Inventory` never puts it on or takes it (no pick-up, no loot, no
  stowing); `ExoMech.server_enter/server_exit` do, with timed animated clips. Left standing, it is
  a frozen `WorldItem` with its plates as hit targets.
- **Weapon:** the WG-50 Walker Gun (.50 BMG), pilot-only, kept on the suit between pilots (the
  pilot's own rifle goes on its rack). Held low and ready at the hip; aimed from the shoulder.
- **Movement:** 260 kg assist, fixed 0.75 pace, no sprint/jump/climb/prone, no vehicle seats.
- **Not built (needs the Captain):** price, repair cost and pilot training (below); AI piloting;
  climbing a dead pilot's suit off his body; a dedicated rig. Numbers are proposed.

### 2.3a Repair cost and pilot training (proposed, Captain's call — flagged as a worry, not a spec)

Two separate asks, two very different costs to build:

- **Repair cost: close to free.** `Prices.repair_cost(item_id, state)` (`economy_prices.gd`) already
  prices any item back to new from its `"integrity"` state (a share of its price for lost
  integrity, a fee per `chips` entry, capped at a max share) — exactly what every plate and vest
  already uses. Once the heavy exo's per-zone plates carry `"integrity"` state like any other armor
  item (2.3's per-part `ArmorRules` work), they're repairable through the existing field-service/
  shop flow for free; no new mechanic needed here, just making sure the new items' data entries have
  sane `price`/`repair` numbers in `data/prices.json`.
- **Pilot training/certification: genuinely new**, nothing in the roster system gates equipment by
  who's allowed to wear it today. Three shapes, roughly rising in cost to build, Captain's call:
  1. **Cash-gated only**: a one-time "certify" purchase per roster soldier (`Economy`), no new state
     beyond a bool on the roster entry. Cheapest to build, weakest as a mechanic (no time pressure).
  2. **Cash + time**: the same bool, but set after a timed base-side activity (mirrors how field
     repairs are already timed jobs) — a soldier is "in training" for some in-game days before the
     flag flips, during which they can't deploy.
  3. **Tied to an existing roster stat** (if one already tracks experience/missions per soldier —
     not confirmed, needs a quick check before promising this shape) rather than a bespoke flag:
     reads as "only veterans get the mech," no new persistent state at all if such a stat exists.
  Recommend starting from shape 2 (cash + time) as the middle ground — mirrors a pattern the game
  already has (timed field-service jobs) rather than inventing a new one, and gives the cost real
  teeth without a new stat system — but this is Captain's call, not decided here.

### 2.4 Naming (proposed, Captain's call to confirm or rename)

No existing in-fiction name exists for any of these four items yet (checked: nothing in
`data/items.json`, `data/vehicles.json`, or the docs). Existing vehicles use a designator-plus-name
style (`UH-60M Black Hawk`, `AH-1Z Viper`); proposed, consistent with that and clear of both
COD:AW's trademarked names and the real aircraft/exoskeleton names they might otherwise echo:

| Item | Proposed id | Proposed display name |
| --- | --- | --- |
| Base VTOL | `vtol_petrel` | VT-14 Petrel |
| Upgrade VTOL | `vtol_razorback` | Razorback (Captain's own name; designator optional) |
| Light infantry exo | `exo_frame_light` | Strider Exoskeleton |
| Heavy mech-class exo | `exo_mech_heavy` | Atlas-pattern Walker |

## 3. Open questions for Captain

1. Unlock mechanism for the Razorback VTOL (cash buy, reputation milestone, story beat) — not
   blocking the base VTOL build.
2. Razorback's nose weapon/sensor pod: ship as a stretch goal later, or fold into its first pass?
3. ~~Heavy exo damage model~~ **Decided (Captain, 2026-10-16): real `ArmorRules` per-part plates
   mapped to the reference art, shootable through, no abstracted pool** — see 2.3.
4. Heavy exo rig: new `CharacterModel` variant needed; not scoped in this doc, needs its own pass
   before that tier is buildable.
5. **New**: repair cost and pilot training/certification for the heavy exo (Captain, 2026-10-16,
   flagged as a worry alongside the damage-model answer, not a confirmed spec) — needs a concrete
   mechanic proposed (not guessed at) before it's built: repair cost scaling, what gates a roster
   soldier from being able to equip the suit, whether training costs time/cash/both.
5. Proposed names in 2.4 — confirm, or Captain's own names (as he did for the Razorback).

## 4. What shipped this session

See `CHANGELOG.md` and the branch's commits for the current state of implementation against this
doc (this doc covers design; it is not updated as code lands).
