# Terror groups and a smaller Black Ridge (proposal)

Status: **proposal, waiting on the Captain's OK.** Nothing here is built yet. Branch
`claude/factions` (from a7e9207), 2026-10-20 19:00 CDT.

The Captain's ask (2026-10-20): "our terrorist organization faction needs to look more like one,
we can keep the black ridge militia but they shouldnt be so big. we should have like islamists and
other terror groups on the map etc", and then "and a cartel or two too".

Every decision is marked **Captain** (he said it) or **Proposed** (mine, for him to approve,
change or drop). All group names, symbols and leaders are made up. They are inspired by real-world
patterns, but no real organisation's name, flag, logo or slogan is used anywhere.

## 1. What's there today

| Piece | Where | What it does now |
|---|---|---|
| Factions | `data/factions.json` | 3 hostiles: Black Ridge Militia (`kit: insurgent`), Vantage Group (`pmc`), Eastern Concord Forces (`concord_ru/ir/cn` by region). Neutral: Salvage Union. Employers: Meridian, US, UK, CA. |
| Black Ridge's kit | `CompoundLevel.HOSTILE_*`, `Kits.INSURGENT` | Light carrier + PE plate + bump helmet + pack. Guns: AKM/AK-74/RPK/PKM/SVD/captured M4. Camo `urban` (grey) with an orange patch. |
| Zone holder | `ZoneControl.controller()` | Falls back to `DEFAULT := "black_ridge"`, so **every one of the 22 contract zones shows Black Ridge** on the theatre map unless a held or offered contract there names another target. |
| Who garrisons a zone | `ZoneLevel._zone_enemy()` | `""` (Black Ridge's mix) unless the deployed contract's target, or a hot zone's holder, fields a non-insurgent kit. `FactionSkirmish.DEFAULT_HOLDER` is Black Ridge too. |
| Contract target | `ContractGen.generate` | An even random pick among the hostile factions (not the employer), so **Black Ridge is about 1 in 3 contracts**. The zone doesn't matter. |
| Hot zones (5) | `WorldSites.site()` | Holder seeded by the zone id's hash among the 3 hostiles; the faction war moves them between enemies. |
| Doctrine | `data/doctrines.json` | `nations`: `insurgent` -> Insurgent, RU/CN/IR -> Regular. Vantage plays PMC. |
| Names | `scripts/ai/names.gd` | Nations US/UK/CA/insurgent/RU/CN/IR. `insurgent` = the region's own people. Both regions (coast, inland) have nation `insurgent`. |
| Looks | `VoxelArt.VARIANTS` | multicam, woodland, desert, urban (Black Ridge), black (Vantage), tan (us), dummy; plain clothes `civ:`. There is no cloth headwear (shemagh, balaclava) and no chest rig. |
| Suicide bombers and VBIEDs | `scripts/campaign/bombers.gd` (wave 6f) | Already built. Only factions on the insurgent kit (Black Ridge today) send them. |
| Story | `data/contracts.json` "story" | Act 1 is against Black Ridge (s1-s3). Vantage arms Black Ridge. |
| Contraband | `data/items.json` | hashish, heroin bricks, captagon, tramadol, cigarettes, counterfeit dollars, unregistered weapons. Mama Rook buys contraband. |

**How big Black Ridge is today:** it holds 22 of 22 contract zones on the map, about 1 in 3
contract targets, all garrisons in a zone whose contract isn't against Vantage or the Concord,
some of the 5 hot zones by hash, and all the bombers. It is effectively "the enemy".

## 2. The new groups

Four new groups: two Islamist terror groups and two cartels (**Captain**: "islamists and other
terror groups", "a cartel or two"). A separatist cell is parked as a maybe for later (section 6).

### 2.1 The Ashen Banner: transnational jihadist network (**Proposed**)

- **What it wants:** a borderless religious rule across the region. The local war is one front of
  many. It wants to drive every foreigner and every army out and to be seen doing it.
- **Where:** it comes in by sea and holds the coast's landing points, then pushes into the cities.
  Its zones: Cove outpost, Landing beach (coast); Ashfield, Red Mesa, Salt pan (inland); and hot
  zone **Old Quarter** (`city_hot`).
- **How it fights (doctrine `jihadist`, new):**
  - aggressive: short engage delay, keeps pushing (`advance_after_s` 4, `flank` 0.4);
  - fights almost to the last man (`morale_broken` 0.15);
  - foreign-fighter cells are its best men (combat 0.6, discipline 0.6); local recruits are poor
    (0.35);
  - IEDs on the roads into its zones (the `ied` threat weighted up);
  - complex attacks: mortars, then an assault wave;
  - takes foreign hostages: aid workers and journalists;
  - suicide bombers and VBIEDs (wave 6f): **Captain's call**, see 5.2.
- **Kit (`banner`):**
  - mixed dark civilian clothes: charcoal, black and sand tunic-and-trouser looks;
  - chest rigs over them;
  - balaclavas or a dark headwrap on most men;
  - captured plate carriers and helmets on the foreign fighters;
  - guns: AKM, Type 56, AK-103, PKM, RPG-7, SVD, and some captured M4/M16A4.
  - Patch (IFF): **red**.
- **Flag and dressing:** a fictional banner, ash-grey with one red arc over a white five-point
  star, and no writing. Flown on poles at its sites and painted on compound walls. Its sites also
  get spray-painted star-and-arc marks.
- **Leaders (HVTs):** the Field Emir (zone commander); the Engineer (bomb-maker, sabotage and HVT
  target); the Recruiter (runs the foreign-fighter pipeline by sea; intel and manhunt target).
- **Relations:**
  - enemies: everyone except the Valley Shura;
  - with the Valley Shura: an uneasy partner (neutral). Neither in `allies` nor `enemies`, so it
    doesn't ripple. Room for a later story beat where they turn on each other;
  - the locals fear it: hitting it never costs rebel support, and freeing its hostages raises
    support.
- **Contracts against it:**
  - HVT capture (Emir, Engineer);
  - hostage rescue (foreign hostages);
  - raid (bomb workshop: an `ied` cache with a new "IED workshop" name);
  - intel grab (the Recruiter's phones and ledgers);
  - sabotage, recon, manhunt;
  - crew rescue: it converges on downed crews.
  - Mostly from the US, UK and Canada.

### 2.2 The Valley Shura: local Islamist insurgency (**Proposed**)

- **What it wants:** foreign troops and contractors out, its own law in the valleys, and the
  militias off the villagers' backs. It is local and has kin in every village.
- **Where:** the inland farm and village zones: Wadi farm, Dry wadi, Scrub Hollow, Thornveld,
  Hollow Downs. No hot zone of its own; its war is in the villages.
- **How it fights (doctrine `guerrilla`, new):**
  - hit and run: opens at long range (engage 260), short bursts, then breaks contact;
  - breaks early (`morale_broken` 0.4) and slips away, rather than dying in place;
  - rarely pushes (`advance_after_s` 10, `flank` 0.3);
  - roadside IEDs are its signature (`ied` threat on most of its contracts);
  - mortar teams from the hills (static weapon teams, G-25, when built);
  - no suicide attacks.
- **Kit (`shura`):**
  - village clothes in flat earth tones (long shirt and trousers: the `civ:` look);
  - a chest rig, a headwrap or a shemagh-style scarf;
  - few plates, and those are old ones;
  - guns: AKM, Type 56, Zastava M70, Mosin (its marksman), RPK, PKM, RPG-7.
  - Patch (IFF): **red**.
- **Flag and dressing:** a fictional pennant, olive with a white mountain-and-river glyph and no
  writing. Flown at checkpoints and on village compound roofs it holds.
- **Leaders (HVTs):** the Elder Commander (a valley's shura head; HVT capture, not kill: his
  capture raises support, his death costs some); the IED Cell Leader (manhunt, raid).
- **Relations:**
  - enemies: Black Ridge (blood feud over the road tax), the Eastern Concord, the allied forces,
    Meridian, and both cartels (it burns their fields and taxes their trucks);
  - neutral with the Ashen Banner.
  - Locals: it has their sympathy. Civilian casualties in its zones cost double rebel support,
    and the `locals_*` contracts never target it (**Captain's call**, see 5.4).
- **Contracts against it:** raid (IED caches), intel grab, HVT capture (Elder Commander),
  manhunt (IED Cell Leader), recon, defend/hold (a village outpost vs its waves), supply line.

### 2.3 The Saltline Syndicate: coastal smuggling cartel (**Proposed**)

- **What it wants:** money. It runs drugs, guns and people in and out through the harbours, and
  fights only to keep the routes open.
- **Where:** the coast's harbours and shore: Harbour yard, Fisher's Reach, Marrow Shore, Mudflat
  Crossing. Hot zone **Reed Delta** (`delta_hot`).
- **How it fights (doctrine `cartel`, new):**
  - professional-ish hired guns: decent aim, short reaction, well fed with ammo (bigger bursts);
  - no zeal: breaks at `morale_broken` 0.35 once the money isn't worth it;
  - guards its warehouses and convoys hard; seldom chases;
  - technicals and armed escorts on every convoy;
  - no IEDs, no suicide attacks.
- **Kit (`saltline`):**
  - civilian clothes in navy, denim and white (work jackets, tracksuits);
  - bought plate carriers on the guards;
  - caps or bare heads, some balaclavas on the hit crews;
  - guns: AK-74M, AKS-74U, M4A1, M16A4, PKM, Glock/P226 sidearms, an SVD for its harbour watch.
  - Patch (IFF): **orange** (militia).
- **Flag and dressing:** no flag. A white hook-and-wave tag stencilled on crates, containers and
  warehouse doors, and a navy pennant on its boats and masts.
- **Leaders (HVTs):** the Harbourmaster (boss; HVT capture), the Bookkeeper (its ledgers are
  intel, and evidence for the story's money trail), the Skipper (runs the boats; convoy and
  supply-line target).
- **Relations:**
  - enemies: Meridian (it raids cargo), the allied forces (interdiction), the Kestrel Cartel
    (turf war over the drug route to the sea) and the Valley Shura;
  - sells guns to Black Ridge (neutral);
  - Salvage Union: rivals over wrecks, but neutral, so no war (Mama Rook buys from it quietly).
- **Contracts against it:**
  - convoy ambush and convoy chase (its trucks);
  - raid (warehouse caches: contraband loot drops, hashish, captagon, counterfeit dollars);
  - sabotage (fuel, boat park, mast);
  - intel grab (the Bookkeeper's ledgers);
  - HVT capture (Harbourmaster);
  - supply line.

### 2.4 The Kestrel Cartel: inland narco cartel (**Proposed**)

- **What it wants:** the valleys' poppy and pill trade, from field to lab to the coast. It rules
  its villages by fear and pays whoever it must.
- **Where:** the river valleys and orchards: Kestrel Valley, Old Orchards, Red Gulch. Hot zone
  **Crow's Pass** (`pass_hot`), its smuggling pass.
- **How it fights (doctrine `cartel`):**
  - the same doctrine as Saltline, but crueller in the brief;
  - roadblocks that tax and kidnap;
  - armed farms and labs;
  - enforcer squads on technicals;
  - ambushes on its roads.
- **Kit (`kestrel`):**
  - work clothes: olive, plaid-brown and denim;
  - chest rigs and a mix of bought and stolen carriers;
  - boonie-style caps, balaclavas on its enforcers;
  - guns: AKM, AK-103, RPK-74, PKP, M70, M4A1, an SVD-S, M1911 sidearms.
  - Patch (IFF): **orange** (militia).
- **Flag and dressing:** a gold kestrel silhouette spray-painted on black. Used on walls, truck
  doors and a black flag over its labs.
- **Leaders (HVTs):** the Patron (the boss; manhunt over two zones), the Chemist (runs the labs;
  HVT capture), the Enforcer (heads its hit squads; its hunter team leader when heat runs high).
- **Relations:**
  - enemies: the Saltline Syndicate (turf war), Black Ridge (the road tax), the Valley Shura,
    the Eastern Concord (on paper; it pays its officers), the allied forces and Meridian;
  - locals hate it: hitting it raises support, as Black Ridge's checkpoints do.
- **Contracts against it:**
  - raid (drug lab: a cache with a new "drug lab" name and contraband loot);
  - the locals contracts (checkpoint, missing villager, stolen stores);
  - convoy ambush, sabotage;
  - HVT capture (the Chemist), manhunt (the Patron).

## 3. Black Ridge, smaller (**Captain**: keep it, not so big)

- **New role (Proposed):** a secular, regional warlord militia from the inland hills. Its men
  are hill-clan fighters and deserters who tax the roads and sell their guns to whoever pays.
  Vantage arms it (story act 1 stays as written). It is the Valley Shura's blood rival: the
  feud over the road tax and the villages gives the faction war a steady local fight.
- **Where (Proposed):** Highland Pass, Greyfell Moor, Pinewood Ridge and Blackwood (inland),
  Gray-box compound (coast, so act 1 still has Black Ridge ground near the LHD), and hot zone **Black Ridge hills**
  (`ridge_hot`). That is **5 of 22 contract zones (23%) instead of 22 of 22**.
- **Fights as now:** Insurgent doctrine, its current kit and urban grey camo with the orange
  patch. It **loses the suicide bombers** (5.2): a road-tax militia doesn't blow itself up.
- **Enemies:** as now, plus the Valley Shura, Kestrel and the Ashen Banner.
- **Contracts:** the story's act 1 (unchanged), locals contracts (its checkpoints and stolen
  stores), convoy ambush, raid.

## 4. The map spread (Proposed)

A new `"controller"` on each contract zone in `data/contracts.json`. `ZoneControl` already reads
it (step 4), so the map and garrisons follow it. Hot zones get a seeded first holder in place of
the hash pick.

| Group | Contract zones | Hot zone | Map colour (IFF) |
|---|---|---|---|
| Black Ridge Militia | compound_01, highland_pass, greyfell_moor, pinewood_ridge, blackwood | ridge_hot | orange (militia) |
| Ashen Banner | cove_outpost, landing_beach, ashfield, red_mesa, salt_pan | city_hot | red (hostile) |
| Valley Shura | wadi_farm, dry_wadi, scrub_hollow, thornveld, hollow_downs | none | red (hostile) |
| Saltline Syndicate | harbour_yard, fishers_reach, marrow_shore, mudflat_crossing | delta_hot | orange (militia) |
| Kestrel Cartel | kestrel_valley, old_orchards, red_gulch | pass_hot | orange (militia) |
| Eastern Concord | none (contracts only) | coast_hot (its Iranian kit) | red (hostile) |
| Vantage Group | none (contracts and rival teams) | none | red (hostile) |

- **Map (Proposed):**
  - the colour stays the IFF side: militia orange, terror groups and armies red;
  - each zone also gets its holder's symbol and name, so two red zones read apart;
  - a new `"side"` field on each faction (`"militia"` or `"hostile"`) replaces the
    "insurgent kit = militia" guess in `ZoneControl.side_of_faction`.
- **Contract targets (Proposed):**
  - a board contract's target is the zone's holder 70% of the time;
  - otherwise it is another hostile active in that region (Vantage and the Concord included),
    so the war stays mixed.
  - Story and flashpoint contracts keep naming their own target.
  - Black Ridge drops from about 1 in 3 contracts to about 1 in 5.
- **Garrisons (Proposed):** a zone's men are its holder's unless the live contract names someone
  else. `""` no longer means Black Ridge. `FactionSkirmish` and `EnemyResponse` read the holder
  too, so the skirmish teams that come in are its real enemies (for example Kestrel vs Saltline).

## 5. Calls for the Captain

1. **Approve the four groups** (names, roles, zones above), or rename or drop any. *Proposed: all four.*
2. **Suicide bombers and VBIEDs** (already built, wave 6f, Black Ridge only today): move them to
   the Ashen Banner only? Or keep them off entirely? *Proposed: Ashen Banner only.*
3. **Red or orange:** terror groups red and cartels orange like Black Ridge, as in the table?
   *Proposed: yes.*
4. **The Valley Shura and the locals:** extra rebel-support cost for civilian casualties in its
   zones, and no locals contracts against it? *Proposed: yes.*
5. **Contract target follows the zone holder 70% of the time?** *Proposed: yes.*
6. **Headwear and chest rigs:** new cloth items (shemagh, headwrap, balaclava, cap: helmet slot,
   no protection) and a `chest_rig` vest (no plates, mag pouches), in 0.5 cm voxels.
   *Proposed: build them after the faces session lands, since the head is FaceArt's now.* Until
   then the groups get their look from clothes colours, chest gear and the patch.
7. **Separatist cell** (section 6): later, or not at all? *Proposed: later.*

## 6. Parked: a separatist cell (Proposed, later)

The Highland Free Front: a small ethnic separatist cell in the moors. It bombs Concord posts and
kidnaps officials, and is willing to work with the company against the Concord. It would be the
first hostile group that can turn friendly (rep above zero). Left out of this round to keep the
map readable.

## 7. Build plan (after the OK)

1. `data/factions.json`: the 4 factions (`side`, `nation`, `kit`, allies and enemies, HVT
   titles), their 4 data kits (with a per-man `variants` list for mixed clothes), and Black
   Ridge's enemies updated.
2. `VoxelArt.VARIANTS`: `banner`, `shura`, `saltline`, `kestrel`. Mixed-clothes looks with a red
   or orange patch.
3. `data/doctrines.json`: `jihadist`, `guerrilla`, `cartel`, and nations for them. `names.gd`:
   nation `foreign` (the Banner's foreign fighters, mixed names), plus HVT titles.
4. Zone spread: `"controller"` on contract zones and seeded hot-zone holders. The
   `ZoneControl.DEFAULT`, `FactionSkirmish.DEFAULT_HOLDER` and `_zone_enemy` fallbacks read the
   zone's holder. Contract target follows the holder.
5. Theatre map: `side` field, symbol and name per zone, IFF colours kept.
6. Site dressing: flag poles, banners and painted marks at each group's compounds, checkpoints
   and HQs (fictional symbols from section 2).
7. Radio chatter: per-group callsigns and lines (`RadioChatter`).
8. Contract types and site names per group (IED workshop, drug lab, warehouse).
9. Bombers gated on the Captain's call 2.

**Tests:**

- factions/kits: each group spawns with its kit and variant;
- contracts: target follows the holder, and Black Ridge's share is at or below 25%;
- map: each group holds its zones, with the right side and colour;
- missions: one contract per group plays;
- smoke.
