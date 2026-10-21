# Terror groups and a smaller Black Ridge

Status: **approved by the Captain 2026-10-20 (section 5) and built on `claude/factions`** (from
a7e9207). Section 9 says what was built and what is left.

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
- **Where (Proposed):** Highland Pass, Pinewood Ridge and Blackwood (inland),
  Gray-box compound (coast, so act 1 still has Black Ridge ground near the LHD), and hot zone **Black Ridge hills**
  (`ridge_hot`). That is **4 of 22 contract zones (18%) instead of 22 of 22** (Greyfell Moor went to the Highland Free Front).
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
| Black Ridge Militia | compound_01, highland_pass, pinewood_ridge, blackwood | ridge_hot | orange (militia) |
| Highland Free Front | greyfell_moor | none | orange (militia) |
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

## 5. The Captain's calls (2026-10-20 ~19:40 CDT, via the question tool)

1. **Groups: Captain, all four** (Ashen Banner, Valley Shura, Saltline Syndicate, Kestrel Cartel),
   names kept as proposed.
2. **Suicide bombers and VBIEDs: Captain, the Ashen Banner and the Valley Shura.** Black Ridge loses
   them. A faction sends them when its data says "bombers": true.
3. **Colours: Captain, as proposed.** Terror groups, the Concord and Vantage red; Black Ridge, both
   cartels (and the Highland Free Front) orange.
4. **The Valley Shura and the locals: Captain, no special rules.** It counts like any hostile for
   rebel support and the locals contracts.
5. **Contract target: Captain, the zone's holder 70% of the time.**
6. **Headwear and chest rigs: Captain, after the faces session lands.**
7. **Separatist cell: Captain, add it now** (section 6).
8. **The living war: Captain, as proposed** (section 7).
9. **A faction's last zone: Captain, "can be sieged but cannot fall unless the player explicitly
   wipes them out".** Wiping out: **Captain, take its HQ and QRF bases in that zone AND kill or
   capture its leaders** (its named HVTs). Until then a front on it never flips it.
10. **The company's ground: Captain, yes, now.** Fronts can open on zones the company took.
    How (Proposed): a front on a company zone posts a defend job (Hold the line) there for the
    company's employer; if the front wins, a flipped zone goes back to the attacker
    (ZoneControl state ENEMY again). The FOB's own zone can be sieged (a defend job, and every day
    the siege lasts costs stores) but never falls, like a faction's last zone.

## 6. The Highland Free Front: separatist cell (Captain: add it now; details Proposed)

- **What it wants:** a free homeland for the highland people, out from under the Eastern Concord.
  It fights the Concord first; anyone else only when they're in the way.
- **Where:** Greyfell Moor (taken out of Black Ridge's five), one small corner of the map. It
  wants the highlands back (its home tag) and the Concord's posts.
- **How it fights (doctrine `guerrilla`, like the Shura):** bombs and ambushes on Concord posts,
  kidnapping officials, sniping from the moors. No suicide attacks.
- **Kit (`highland`):** woodland-pattern smocks and old Concord surplus (helmets, carriers),
  AK-74, AKS-74U, SVD, RPK-74, RPG-7. Patch: **orange**.
- **Flag:** a fictional pennant, slate blue with a white mountain peak over three bars, no writing.
- **Leaders (HVTs):** the Commandant, the Bomb-maker.
- **Relations:** enemies the Eastern Concord, Black Ridge and the Ashen Banner. Neutral to the
  company's employers at the start (start rep -10, so it can be won over): **the first hostile that
  can turn friendly.** At rep 0 and up it fights alongside the company in skirmishes (it already
  would: FactionSkirmish sends a faction the company gets on with as friendly).
- **Contracts against it:** from the Concord-aligned side only (Meridian, the rare job): HVT
  capture, raid. **Contracts for it (later):** jobs against the Concord, once its rep allows.

## 7. A living war: zones change hands (Captain, 2026-10-20)

The Captain: "the world needs to feel dynamic, zones change hands. different factions fight over
different areas for different reasons". The how below is **Proposed**.

### 7.1 What exists to build on

- **`WorldSites`** (wave 6c): a hot zone's holder, grip (0..1) and flashpoint flag, saved in the
  campaign section `world_sites`.
  - A contract won against the holder takes 0.3 grip.
  - Each day (`Economy.advance_days`) a grip at or under 0.3 has a 20% chance to flip to one of
    the holder's enemies; otherwise grip repairs 0.06 a day.
  - It only covers the 5 hot zones, and its random roll is unseeded (not deterministic).
- **`ZoneControl`**: the theatre map's controller, side and contested flag
  (`server_set_controller`), and the company's own zone flips (HQ and QRF bases down).
- **`FactionSkirmish`**: a team of the holder's enemy hits one of its sites while the squad is
  in the zone (60% every 12-20 min).
- **`EnemyCommand`** and **`Pressure`**: within one deployment in a hot zone, the enemy's
  reserves, counterattacks and reoccupation.
- **`RebelSupport`**: per region, 0-100, up with help and down with civilian casualties.
- **`RegionMap.links()`**: which zones border which (the crossings).
- **`Contracts.server_refresh_board`**: already posts a flashpoint's own war job.

### 7.2 Every zone has a holder, a grip and a front

- `WorldSites` grows from 5 hot zones to **every enemy-held zone** (all 22 contract zones and 5
  hot zones), seeded from section 4's spread.
- Each row gets new fields:
  - `front`: the attacker, and since which day;
  - `progress` (0..1): how much of the zone the attacker holds;
  - `since_day`.
- Zones the company holds are out of the war (call 10).
- `ZoneControl` reads the row:
  - its holder is the controller;
  - a zone with a front is **contested** (the hatching the map already has).

### 7.3 What each faction wants, and why

Each zone gets **asset tags** from what's on it. Most are already in its modules; the rest are a
few new tags in `data/contracts.json`:

| Asset tag | Where it comes from |
|---|---|
| `village` | village and town modules |
| `mosque` | the town modules (and a new `mosque` tag on village zones that have one) |
| `crossing` | checkpoints, and zones on a region's edge |
| `route` | zones on the coast-to-inland road chain |
| `harbour` | coast zones with water |
| `oil` | new data tags on salt_pan, red_mesa, thornveld |
| `airfield` | new data tags on ashfield, landing_beach |
| `hq` | hq and qrf_base modules |
| `fields` | new data tags on kestrel_valley, old_orchards, wadi_farm |
| `home` | each faction's starting zones |

Each faction weights the tags (a new `"wants"` map in `data/factions.json`):

| Faction | Wants most (weight), and why |
|---|---|
| Ashen Banner | oil 3, airfield 3, hq 2, mosque 1: money and spectacle; seize what the world notices |
| Valley Shura | village 3, mosque 3, fields 1: the people, the pulpits and the recruits |
| Saltline Syndicate | harbour 3, crossing 3, route 2: the routes the goods move on |
| Kestrel Cartel | fields 3, route 3, crossing 2: field to lab to the coast |
| Black Ridge | home 4, crossing 2, route 1: its home valleys and the road tax |
| Eastern Concord | hq 3, airfield 3, crossing 2: strategic sites and the border |

A zone's **worth** to a faction is the sum of its tag weights. That is why the Shura fights over
villages and the cartels over crossings.

### 7.4 Each faction's strength

- **Strength** (0-100), one number per faction, saved in the campaign section.
- **It rises** each day:
  - from its zones' worth to it (income);
  - more slowly for a predatory group in a region where rebel support is high (7.6).
- **It falls** with:
  - its men the company kills (the `heat_kill` hook): 0.2 each;
  - a contract won against it: 6;
  - an HQ or QRF base of its taken out: 10;
  - a lost attack: 8.
- Strength is what an attack is made of, and what a holder defends with.

### 7.5 The daily war tick (host, deterministic)

- **When:** `Economy.advance_days`, once per day passed.
- **Deterministic:**
  - the roll for zone Z on day D is `RNG(hash(war_seed, D, Z))`;
  - `war_seed` is set once when a campaign starts and saved;
  - the same campaign plays the same war, and a reload changes nothing.
- **1. Fronts resolve.** Each zone with a front:
  - the attacker's progress moves by (attacker strength × worth − holder strength × grip) ×
    0.1, plus a small roll;
  - at progress 1 the zone **flips**:
    - new holder at grip 0.55;
    - flashpoint (a war job);
    - a news line;
  - at progress 0 the attack **fails**: the front closes, the attacker loses 8 strength, and a
    news line goes out;
  - a front open more than 6 days stalls and closes.
- **2. New fronts.**
  - Only while fewer than **3 fronts** are open (call 8).
  - Each faction with strength over 40 and no front of its own may attack.
  - Its target is the best-worth zone **bordering one it holds** (`RegionMap.links`) whose holder
    is one of its enemies.
  - It attacks when that target's holder is weak (grip × holder strength low enough).
  - Weak grips draw attacks first: the 0.3 contested grip stays the trigger.
- **3. Grip repairs** 0.06 a day where there's no front (as now).
- **Pace:** with these numbers, about one zone changes hands every 2-3 days of campaign time.
  Tuned in tests, not playtests.
- **Never:**
  - a faction's last zone (call 9);
  - company or FOB zones (call 10);
  - a zone where the squad is deployed right now (it resolves after the debrief).

### 7.6 The player's actions shift it

- **Hitting a faction** weakens it:
  - a contract won against the holder takes its grip (0.3, as now) and strength (6);
  - in a contested zone, the win also moves the front 0.25 away from whoever the company hit;
  - kills drain strength (7.4).
- **Taking out an HQ or QRF base** knocks 0.15 grip on top, saved even without a contract.
- **Rebel support helps the locals** (Proposed):
  - at 40 and up in a region, the predatory groups' (Black Ridge, both cartels) grip there
    repairs at half speed;
  - at 60 and up, their strength income there is cut by a quarter: villagers stop paying the tax;
  - at 80, the locals' rebels contest a weak predatory zone themselves. That opens a front with
    "rebels" as attacker, and a win makes it **neutral** ground, held by the locals.
  - Low support (under 20) does the opposite for the Valley Shura: the people turn to it.
- Working for an employer on a front (for example a US job against the Banner in a contested
  zone) is how the company takes sides.

### 7.7 The player sees it

- **News at the base** each morning:
  - a short "overnight" list on the base screen and the board, read out as the liaison's or a
    local stringer's radio line;
  - example: "Overnight: the Valley Shura took the Dry wadi checkpoint from Black Ridge.
    Fighting goes on at Red Gulch between the Kestrel Cartel and the Saltline Syndicate.";
  - lines are built from the zone's best-worth site.
- **Looted enemy radios** (`RadioChatter`) carry per-group lines about the front: "Hold the pass,
  the cartel's trucks are coming up from the river".
- **Theatre map:**
  - control colours (IFF) and contested hatching update each day;
  - an arrow from the attacker's neighbouring zone shows each front;
  - the zone tooltip names who is attacking whom, and why ("the Shura wants the villages").
- **Deploying into a contested zone, the fight is already on:**
  - the attacker holds `progress` × the zone's sites: its garrisons in those, the holder's in the
    rest;
  - a `FactionSkirmish` team is mid-assault on a site near the line when the squad lands (the
    first skirmish at 30-60 s, not 5-10 min, and at twice the size);
  - more skirmishes come for the whole deployment.
- **Refugees:**
  - in a contested zone, civilians walk out along the roads in families of 3-6 with bundles,
    toward the neighbour that isn't at war;
  - the front's villages are half empty;
  - a flipped zone's villages refill over 3 days.
  - Built on the existing PeopleLayer civilians.

### 7.8 Contracts follow the war

- The board weights zone picks toward **fronts** (×3) and **zones flipped in the last 3 days**
  (×2); quiet zones are ×1.
- Every new flip posts a flashpoint war job, as hot zones do today, now for every zone.
- Each front's employer offers fit its side:
  - the US, UK and Canada against the Banner and the Concord;
  - Meridian against whoever sits on its routes;
  - the locals' contracts against the predatory groups.
- A war job's brief says who is fighting whom ("The Kestrel Cartel is pushing into Red Gulch;
  the Syndicate is holding. Meridian wants the Syndicate's convoy stopped while it's stretched").
- The target follows the zone holder (call 5). On a front, it is the holder or the attacker,
  whichever the employer is at war with.

### 7.9 Saved, host-authoritative, synced

- **Saved:** everything lives in the campaign section `world_sites`: rows, faction strength,
  `war_seed`, and the last 10 news lines.
- **Host only:** the host runs the tick.
- **Synced:** `Economy._public` already carries `world_sites` to every peer; strength and news
  ride along.
- **Old saves:** a save from before this seeds the new rows from the spread on load. Hot zones
  keep their saved holder.

## 8. Build plan (after the OK)

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
10. The living war (section 7), in its own commits:
    - `WorldSites` for every zone, with fronts, progress and strength;
    - the zones' asset tags and the factions' `wants`;
    - the deterministic daily tick;
    - the player's effects and the rebel-support effects;
    - the morning news and radio lines;
    - map fronts (arrows and hatching);
    - split garrisons and an early skirmish in contested zones;
    - refugees;
    - board weighting toward fronts.

**Tests:**

- factions/kits: each group spawns with its kit and variant;
- contracts: target follows the holder, and Black Ridge's share is at or below 25%;
- map: each group holds its zones, with the right side and colour;
- missions: one contract per group plays;
- world sites:
  - the war tick is deterministic (same seed, same war);
  - a zone flips once an attack wins, and the last zone never falls;
  - a contract win moves a front;
  - the board leans toward fronts;
  - news lines appear;
  - a contested zone spawns both sides;
- smoke.

## 9. What was built (2026-10-20) and what is left

**Built:**

- **Factions** (`data/factions.json`). The five groups have:
  - `side`, `doctrine`, `bombers`, `war_wants`, `symbol`, `leaders`, `wants_text` and `radio`;
  - their data kits, with mixed plain clothes through the kit's `clothes`.
  - Black Ridge, Vantage and the Concord got `side`, `symbol` and their `war_wants`; Black Ridge
    and both cartels are `predatory`.
- **Kits** (`Kits`):
  - `variant(kit, index)` picks a man's clothes;
  - `is_uniform` covers the Banner's foreign fighters and the Front's smocks;
  - `dress()` gives a man's clothes, his orange or red marks, and his `faction_id`;
  - `doctrine()` and `sends_bombers()`.
- **Spawns:** every hostile spawn path wears its faction's dress, so SquadAI fights by the
  faction's own doctrine. These are garrisons, QRF waves, EnemyResponse teams, skirmishers and
  bombers.
- **Looks:** VoxelArt variants `banner` and `highland`.
- **Doctrines:** `jihadist`, `guerrilla` and `cartel`.
- **Zone spread** (`data/contracts.json`): every zone has a `controller`, `assets` and `home`.
  - `ZoneLevel._zone_enemy` reads the zone's holder, so `""` no longer means Black Ridge.
  - A board contract's target is the holder 70% of the time (`ContractGen.HOLDER_SHARE`).
- **The living war** (`WorldSites`, campaign sections `world_sites` and `war`), all of section 7:
  - strength, the daily tick, fronts, flips, sieges, and wipe-outs with leaders;
  - fronts on the company's ground (`ZoneControl.server_lose_zone`);
  - the player's effects and the rebel-support effects;
  - news, and the stringer's overnight radio line.
- **The map:**
  - `Theatre` rows carry the front, its why, the holder's flag and what the holder wants;
  - `WorldMapView` draws front arrows, a front badge and holder flags;
  - `WorldMapScreen` has a War news panel.
- **In a contested zone:**
  - the attacker holds a share of the outposts, checkpoints and villages (`ZoneLevel.module_faction`);
  - an assault is under way within a minute, twice as big (`FactionSkirmish`);
  - villages are half empty, and refugee families walk out (`PeopleLayer`).
- **Flags:** at the holder's sites (`FactionFlags`). The cartels put up a stencilled board
  instead.
- **Radio:** each group's lines, and talk about the front (`RadioChatter`).
- **Board:** a job on every front, and a war job on every flip (`Contracts.front_offer`).

**Follow-ups built (2026-10-20, branch `claude/faction-followups`):**

- **Site names** (`factions.json` `site_names`, `ContractGen.faction_site_name`): a raid's or
  supply line's cache is an "IED workshop" for the Banner and the Shura, a "drug lab" or a
  "warehouse" for the cartels (one per site, the same every time). Not on the locals' jobs.
- **Contraband** (`loot_tables.json` `factions`, pools `contraband` and `contraband_pocket`):
  - a box of the cartel's goods beside the target of a raid, sabotage or supply-line job against
    it (`ContractGen.mission_target` marks it `loot_of`; `PeopleLayer` places the box when the
    contract goes live; not by an optional bonus target);
  - every third man of a cartel garrison carries some (`WorldValuables.pocket_contraband`,
    `ZoneLevel`).
- **Named leaders** (`WorldSites.next_leader`): an hvt_capture or manhunt job against a faction
  is after its next leader still free, in the title, the brief and the objective ("Capture the
  Chemist (name)"). The contract keeps the title (`leader`), and winning it takes that leader
  down (`server_leader_down` takes the named one, else the next free), in a contract zone too.
  Each leader has a PersonLook HVT role (`leader_roles`): commander, financier or bomb maker.
- **Doctrines:** the Concord fights as `regular` and Vantage as `pmc`. Vantage's racing team is
  tagged as Vantage's men (`EnemyResponse._spawn_team`), not the zone holder's.

**Left (Proposed follow-ups):**

- Cloth headwear (shemagh, headwrap, balaclava, cap) and a chest rig, after the faces session
  lands (Captain's call 6).
- Two HVT jobs on the board can name the same leader; the second one won takes the next leader
  free instead.
- A Highland Free Front that turns friendly gets contracts of its own against the Concord.
- Refugees only walk to the zone's edge. Moving them into the neighbouring zone, and back after
  a flip, is still to come.
