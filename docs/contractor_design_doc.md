# Contractor Design Doc

Oct 9, 2026 · @Captain

## Overview

Contractor is a near-future tactical FPS where every piece of gear physically exists on a body, in a pack or in a vehicle, and a persistent campaign makes salvage and logistics the main source of tension. It is single-player or co-op against AI only; there is no PvP. This doc builds on the brainstorm handoff in the project files; anything the handoff marks as unconfirmed is flagged as a proposal here too.

**Pitch.** Take a contract, kit out your squad and your vehicle, drop into a warzone that is already burning, and get out with whatever you can physically carry. What you bring home, and who you bring home, shapes every contract after it.

**Pillars.** Every mechanic must serve at least one of these, or it gets cut as a UX tax.

| Pillar | What it means in play |
| --- | --- |
| Tension | Without human opponents, pressure comes from mission clocks, escalating factions, scarcity and the risk of losing gear or squadmates. |
| Readability | You can see a soldier's role and state from their silhouette: plates, rig, pack size, what is in their hands. |
| Tactile fantasy | Items are handled, not menu-sorted: mags sit in rig slots, packs fill with real volume, objective items take two hands. |
| Logistics | Carry capacity, vehicle cargo and squad trust decide how much salvage you can turn into profit. |

**Audience and platform.** PC first, mouse and keyboard plus controller, for players of Arma 3, MechWarrior 5 and extraction shooters who want persistence without PvP. Consoles are out of scope until the core loop is proven.

**Touchstones.** MechWarrior 5 for the contract campaign, Arma 3 for combined-arms sandbox and squads, its LAMBS Danger.fsm and VCOM mods for AI behavior, ACE3 medical with KAT for the medical system, Marathon, Beta Decay and Star Citizen for the feel of inventory and armor (Star Citizen for inventory and armor only).

**Build.** The game is built in the [Contractor repo](https://github.com/cghath/Contractor) (v0.1.0 plus unreleased phase 2 as of 2026-10-09). The repo README's locked design decisions and roadmap phases are the source of truth for what is built; this doc covers the design around them. Where the two disagree, the item is listed under Conflicts with the build at the end.

## Core loop

One contract is one pass through five steps, and the campaign carries everything forward. This is the working loop from the handoff; it came out of the brainstorm and Captain has not confirmed it yet.

&#91;embedded content: core loop · 5 steps per contract\]

The haul-out step is where the pillars meet: the squad can only bank what it physically carries, so every earlier choice (salvage share, pack size, vehicle cargo) pays off or fails there.

| Step | The decision that matters | Main pillar |
| --- | --- | --- |
| 1 Take a contract | A contract zone or a hot zone, then more cash now or a bigger salvage share you must carry out yourself | Logistics |
| 2 Assign loadout | Light and fast through tight routes, or heavy with room for loot | Tactile fantasy |
| 3 Drop into the AO | Where to enter a fight two factions are already having | Tension |
| 4 Objective, haul out | What to leave behind when packs, hands and cargo are full | Logistics, tension |
| 5 Base turnaround | Which squadmates and gear to repair or replace with limited money | Logistics |

**Long arc.** Across contracts, reputation with a faction unlocks its troops as support in warzones. With enough reputation the player builds their own faction from the ground up.

### Missions: contract zones and hot zones (decided)

Captain set two kinds of deployment. Contract zones run one contract at a time; hot zones are larger active areas where one faction offers several contracts in a single deployment, like a raid.

|  | Contract zone | Hot zone |
| --- | --- | --- |
| What it is | A location built for one contract, played contract to contract | A larger active area the player deploys into, bearing multiple contracts |
| Who offers the work | Any employer faction | One faction, which offers all the contracts in that zone |
| Shape of a deployment | Drop, complete the contract, haul out | Deploy, take contracts from that faction inside the zone, raid-style |
| What it stresses | Short, focused runs and steady campaign income | Endurance: ammo, medical supplies, carry space and squad health across several contracts |

In a hot zone the loop's steps 3 and 4 repeat inside one deployment before the squad returns to base, so carry capacity and the vehicle's cargo matter even more there. Both kinds of zone are nodes on the repo's zone-graph world map, and each keeps its own saved state (looted and dropped items, voxel damage), which the build already does for the test compound. Decided: the squad can hold several contracts at once, resupply and bank loot mid-zone, and the deployment ends when it extracts. Hot zones need no reputation minimum but are considerably harder, while contract zones only offer up to medium-tier weapons, armor and gear as loot and salvage, scaled by difficulty (Captain).

**Missions (decided in the mission brainstorm).** Contracts come from a regional contract board for regular jobs, and from faction contacts and fixers for special, high-pay jobs that relationships unlock. They are negotiated MW5-style, trading pay against salvage share and support budget. Pay comes as an advance plus completion pay (Captain); proposed: the advance is about 30%, kept even if the contract fails, with the split negotiable. Each contract shows a 1 to 5 difficulty rating, set by enemy size and quality, plus known threats such as armor or AA; better intel makes the estimate more accurate. The rating is sometimes wrong: a client may lowball the threat or the intel may be stale, so a briefing occasionally understates what the squad will face, and the squad can renegotiate or abort when that happens (Captain). The first playable mission types are raid (destroy a cache or AA site), HVT capture, hostage rescue and intel grab. Some hot zones also offer LRRP missions, where a small team goes deep into enemy ground to uncover intel. An LRRP is run by a detached team of 2 to 4 squad members (players and/or AI), while the rest of the squad waits at the LHD or FOB or works another contract. A compromised LRRP isn't failed: the team can break contact and evade, shake pursuit and keep going, or call an emergency extraction. Intel comes back two ways: enemy positions marked and reported by radio bank immediately, while photos and captured documents only count once carried out, so anything not yet sent back is lost if the team goes down. An LRRP can run for several in-game hours, with time acceleration while the team lies up in a hide, and fatigue matters; food and water simulation is deferred, not a priority for now (Captain). Hot zone layout (proposed): one enemy HQ, 3 to 6 outposts, road checkpoints, roaming patrols and 1 or 2 QRF bases with vehicles, with contracts on or near those sites. Destroying parts of that structure weakens the enemy across the zone: a destroyed QRF base stops its reinforcements, a destroyed comms site slows their response, and killing officers makes patrols less coordinated. Hot zones also use an alert level: the zone starts calm, noise, sightings and losses raise it (more patrols, closed checkpoints, QRFs on standby), and it eases when the squad goes quiet. There is no alert meter on screen: players read alertness from intercepted radio chatter, patrol activity and closed checkpoints. Looting an enemy radio lets the squad hear that zone's chatter, revealing the alert level and sometimes patrol or QRF movements, until the enemy notices and switches frequencies. Better-equipped factions can call mortars, armed helicopters or drones on the squad at high alert, and destroying their comms or mortar sites removes that threat. Drones can be shot down, or a player can carry a jammer, a heavy inventory item that blocks drones and radio nearby, including the squad's own radio. The squad has drones too: small recon quadcopters that fly out to scout and mark enemies, with limited battery, and can be shot down or jammed, and FPV attack drones are a buyable item. A hot zone deployment is a staged insertion: players insert at the zone edge, or by helicopter or AAV from the LHD or FOB, then push in, and contracts appear on the map as they are taken from the board. New contracts also come in over the radio during the deployment, often reacting to what the squad has done ("you hit their QRF, now hit the HQ"). Enemy pressure rises the longer the squad stays: the enemy commits bigger QRFs, armor and hunter teams over time, so staying pays more but gets riskier (Captain). Civilians are on the map. Hitting one costs a fine from the pay plus reputation with the hiring faction and the locals, and at 8 such casualties the contract is voided and pays nothing. Only civilians hit by the players or their AI count, not those killed by other factions. Rival contractor teams are a recurring enemy: often the rival PMC's squads, though other rival firms exist too, and later in the story the rival PMC can also send hit teams after the player (Captain). Hostile factions can send bounty hunters: a heat meter brings generic hunter teams, and at high heat named, persistent hunter squads that remember the squad show up, Nemesis-style. The early game is mostly fighting terrorist factions (Captain). Campaign time is a hybrid: missions advance the clock, and travel between regions, recovery and repairs also take days (Captain); proposed: wages and upkeep are paid weekly, like MW5. Contracts are mostly generated from templates, driven by the faction war and intel, with a few handmade story contracts for key campaign beats. The story mixes a loose main storyline with per-faction arcs that unlock as reputation grows. In the main plot, a rival PMC is the face of a conspiracy fueling the regional war, and the player's intel slowly uncovers who is behind it, leading toward the late-game player faction (Captain). A multi-deployment campaign-operation tier exists as late-game scope, part of the player-built faction (Captain). Friendly HVTs cooperate. Hostile HVTs try to expose the squad, run and resist until zip-cuffed. Any HVT can be carried or loaded into a vehicle's passenger seat (Captain). Intel is a physical item (laptops, phones, documents) found by looting enemy squad leaders and officers, and at outposts and military checkpoints. Bringing it back opens leads to new contracts, caches or HVTs, and it can also be sold to other factions at the risk of angering the client. The model is the persistent recovery mission in Arma 3's Sefrou-Ramal (Captain). Captain doubled the world size and the mission lengths to match: a contract zone is about 2 to 4 km² and 40 to 90 minutes, and a hot zone about 8 to 16 km² and 2 to 4 hours (reading doubling as twice the area; if Captain meant twice the width, hot zones become about 16 to 32 km², being confirmed). Players still choose when to extract, and mission timers stay forgiving for now (Captain). Each deployment starts with an Arma-style map briefing and planning phase: it shows enemy positions known from intel, and players mark their plan and insertion point and pick supports (Captain). Players choose how to insert (helicopter, AAV, ground vehicle or on foot) unless the client fixes it, and weather and terrain limit the options: heavy storms ground helicopters, and AAVs are no use in the mountains (Captain). Each mission ends in a full debrief: pay earned, bonuses and penalties, salvage to claim, casualties and injuries, reputation changes and intel turned in (Captain). Details are in the [mission brainstorm doc](https://claude.ai/code/artifact/504b59c6-2729-45a1-8709-6fa39892c701).

## Key systems

Five systems carry the loop; physical inventory and squad AI are the two that the rest depend on, so they get built and proven first.

### Physical inventory (settled)

- **Armor and rig slots.** Plates, rigs and armor have slots built for specific items (magazines, a sidearm), so carried gear sits visibly on the body.
- **Physicalized backpacks.** A pack's interior is a real volume that fills with whatever the player or an NPC picks up.
- **Volume in litres.** Every item has a volume in litres and every container a capacity: pockets 2 L, carriers 3, 6 or 8 L, plus the backpack, as built. The handoff named cSCU as the unit (see Conflicts with the build).
- **Hands as inventory (proposal).** Bulky objective items take two hands: carry the reactor core with a sidearm out, or drop it and fight.
- **Bag as collider (proposal).** A big pack will not fit vents or narrow breaches, so the best route is the one you take light.
- **Rules.** No random hit-location destruction of loot. Mag-by-mag ammo tracking is not a selling point on its own.

### Voxel destruction and armor (built)

- **Destructible structures.** World structures are 10 cm voxels; bullets carve holes, and the host keeps damage as an edit log that is saved with the zone.
- **Voxel armor.** Plates and helmets are 1 cm voxel objects that chip where hit. How armor stops rounds is set in Armor, plates and helmets below; the voxels stay as the visible damage.
- **Item state travels.** Rounds loaded and armor chips belong to the item, so a dropped plate keeps its holes for whoever picks it up.

### Armor, plates and helmets (decided)

Plates should behave like real plates (Captain). Today's build treats a plate as voxels that only fail where a hole has been chipped through. The proposal keeps the voxels as the visual and adds how each material actually fails. Material behaviour below is from general knowledge and needs checking; all numbers are proposed starting values.

**Armor ratings (decided: NIJ scale).** Every round has a threat level, and every vest, plate and helmet has a rating on the same NIJ ladder (Captain). Armor stops a round when its rating is at or above the round's level, and lets it through when it is lower. Any aramid layer stops fragments. Ceramic cracks, steel spall and impact damage apply on top of the rating. The ladder uses NIJ names but the game's own order, not strict NIJ (Captain): the light plate stops regular .223 at most, so .223 ball sits below 7.62x39 and .308 ball here.

| Level | Rounds at this level (proposed) | Armor with this rating |
| --- | --- | --- |
| IIA | 9mm, .45 ACP, buckshot | Light vest, front only (proposed); light helmet (proposed) |
| II | .357 Magnum, hot 9mm | None yet |
| IIIA | .44 Magnum, 10mm, .357 SIG, shotgun slug | Medium and heavy vests (proposed); medium helmet (proposed) |
| III | 5.56 / .223 ball (M193) | Light plate (Captain: stops regular .223 at most) |
| III+ | 7.62x39 mild steel core, 7.62x51 / .308 ball | None yet |
| III++ | 5.56 M855 green tip, 7.62x54R steel core | Heavy helmet (Captain); medium plate (proposed) |
| IV | Armor-piercing rifle: .30-06 M2 AP, 7.62x51 AP, 5.56 AP | Heavy plate (proposed) |
| Above IV | .50 BMG / 12.7 mm | Nothing; it defeats all body armor |

In real NIJ testing, .308 ball is Level III and .223 ball is III+. The game swaps them on purpose (Captain) so the light plate stops .223 ball and nothing heavier.

| Material | Highest rating it can carry (proposed) | Under repeated hits |
| --- | --- | --- |
| Ceramic (decided behaviour) | Up to IV when fresh, so the only material for heavy plates | Each hit cracks the plate around it. A later hit inside a cracked zone is much more likely to get through, and enough hits destroy the plate (Captain) |
| Steel | Up to III++; armor-piercing goes through | Doesn't crack, so it takes many hits in one spot. Bullet splash (spall) can wound the neck, arms and face unless the plate has an anti-spall coating |
| Polyethylene | Up to III, so light plates only | Lightest. Doesn't crack but deforms, and repeated hits in one spot let rounds through |

**Ceramic crack zones (proposed).**

- Each hit cracks a zone about 5 cm around the impact. A round landing in a cracked zone has its chance of being stopped cut by about 30% per earlier hit in that zone.
- The plate has an overall integrity. Each hit takes off a share by round class; at zero the plate shatters and stops nothing.
- Cracks belong to the plate's item state, so a cracked plate keeps its damage when dropped, looted or swapped, and a player can inspect it.
- Vests are aramid-fiber soft armor, the family Kevlar belongs to, and the plates in them provide the higher protection (Captain). Proposed: the aramid behind and around the plates stops pistol rounds and most fragments but not rifle rounds, and it still protects after a plate fails. Areas the vest covers without a plate (sides, shoulders, collar) get that aramid protection only.

**Vest tiers (decided).** All vests are aramid-fiber soft armor (Captain).

| Vest | Plates it takes | Fragment protection | Spall protection with steel plates |
| --- | --- | --- | --- |
| Light | Light plates only; light plates fit no other vest (bespoke). A light plate stops up to standard .223 ball (Captain), which puts it at III on the game's ladder | Front only. The light vest also stops some ballistic threats there (Captain); proposed rating IIA | None beyond the plate face |
| Medium | Medium or heavy plates (interchangeable) | Front and back | Neck covered; arms can still catch spall |
| Heavy | Medium or heavy plates (interchangeable) | Front, back and sides | Neck, face and arms covered |

So steel plates trade spall risk for durability, and a heavier vest is how you buy that risk back.

**Helmets (decided).** Helmets are an aramid fiber and composite hybrid, in light, medium and heavy tiers (Captain). Like plates, a helmet stops the rounds its tier is rated for, and a stopped round still deals impact (see Impact damage below).

| Helmet | Rating and what it stops |
| --- | --- |
| Light | IIA (proposed): fragments, 9mm, .45 ACP and buckshot |
| Medium | IIIA (proposed): fragments and all pistol rounds up to .44 Magnum, plus shotgun slugs |
| Heavy | NIJ III++ (Captain): fragments, all pistol rounds, and rifle rounds including 5.56 ball and M855 green tip, 7.62x39 mild steel core and 7.62x51 ball. Armor-piercing rounds such as M2 AP still go through. Every stop still deals heavy impact |

This changes the repo's locked armor rule, so it is also listed under Conflicts with the build.

### Damage and medical (decided: no hitpoints)

There is no health bar. Damage works like ACE3 and KAT: a hit makes a wound on a body part, wounds drain a real blood volume, and blood loss, pain and breathing decide when a soldier slows, goes unconscious or dies. Captain chose a middle ground: real values (blood volume, arterial bleeds, fractures, vented chest seals) but only about ten kit items, so the number of actions stays small. The model and numbers come from the [mod research doc](https://claude.ai/code/artifact/837553d8-88f9-4d66-894b-b409aca402d7) sections "Medical model to Captain's spec" and "Other damage and injuries"; every value is a starting point for Captain's playtests.

| Layer | How it works (starting values) |
| --- | --- |
| Blood | 6 L for every soldier (Captain), about 70 mL/kg for an average 85 kg male soldier. Effects are set by the share lost, not litres, and scale smoothly (see Blood loss effects below): unconscious at 40% lost (3.6 L left), cardiac arrest at 50% lost (3.0 L left). Blood only comes back through IV or IO access plus a bag of fluid or blood during a mission |
| Bleeding | Rate scales with the heart's output, so casualties fade rather than drain evenly. These are the rates for a fully hit vessel at full blood; partial hits scale down: arterial (thigh, upper arm) 1.2 L/min, roughly 2 to 3 minutes to unconscious; junctional (groin, armpit, neck) 0.8 L/min; large muscle 0.25 L/min; graze 0.03 L/min; a broken femur 0.05 L/min internally until splinted |
| Where it hits | Decided (Captain): major arteries and veins are simulated as paths inside every body, along with a body map of lungs, heart, brain, arm bones and leg bones, with everything else counted as tissue (Captain). A channel through the chest is a penetrating chest cavity wound on top of whatever it hits. Proposed results: brain hit is fatal; heart hit means cardiac arrest within seconds; lung hit is an open chest wound; bone hit rolls a fracture by round class; tissue is a muscle wound. A round that gets past armor traces a wound channel through the body. Each vessel or organ near the channel bleeds or is damaged by how close the round passed, multiplied by the cavitation (the temporary wound cavity) that may or may not reach it. A direct hit on a vessel gives its full bleed rate; a near miss inside the cavity gives part of it; outside the cavity it is a plain muscle wound. Proposed cavity reach to tune: pistol about 2 cm, intermediate rifle about 5 cm, full-power rifle about 7 cm |
| Tourniquet | Stops all bleeding below it, adds pain, and a leg tourniquet forces a limp. A badly placed one (over a joint, or rushed under fire in under 2 s) cuts bleeding by only 70%, and a second one beside it is the fix. A medic can pack the wound and remove it in field care |
| Fractures | Chance when a bone is hit: pistol 25%, intermediate rifle 70%, full-power rifle 95%, fragments 20%. A broken leg means walk only and heavy pain; a broken arm means high sway and slow reloads. A splint restores walking and jogging, but no sprint until the mission ends |
| Chest | A hit past armor in the lung zone is an open chest wound and oxygen falls slowly. Without a seal there is a 50% chance of tension pneumothorax within 60 to 120 s, then cardiac arrest about 90 s later. A vented seal stops it; a non-vented or improvised seal has a 30% chance of tension later and needs burping. Decided (Captain): breathing is simulated, including oxygen exchange and alveolar efficiency. Proposed: each lung has an efficiency from 0 to 1 that falls with fluid in the lung (blood from a lung hit or hemothorax), a collapsed lung (pneumothorax) and similar damage, and SpO2 follows from that exchange, the breathing rate and blood volume. Oxygen is hidden: players hear laboured breathing and see vision grey out, and a medic reads it on a pulse oximeter |
| Pain and unconsciousness | Pain runs 0 to 1 (an arterial or rifle wound adds 0.6 to 0.9, a graze 0.1 to 0.2) and fades over about 15 minutes. The knockout threshold is 0.9 at full blood and drops to 0.6 at 30% lost; at 40% lost you are out whatever the pain. Once stable, a casualty rolls to wake every 15 s at 15% |
| Cardiac arrest | Decided (Captain): losing a lethal amount of blood stops the heart and starts a 10-minute window, replacing the flat 60 s bleed-out. The casualty counts as unconscious the whole time. Inside it the team can do CPR, defibrillate, give epinephrine, adenosine and blood, and treat wounds. If there is still no heart rate, no SpO2 reading and a blood pressure of 0/0 when the 10 minutes run out, the unit dies (permadeath for AI squadmates; players respawn). Decided (Captain): the only way to reverse hemorrhagic shock is to put blood back in, so CPR and the defibrillator can't restart the heart until volume is restored (proposed: back above 60% of volume, 3.6 L). The IV comes first |

**Simulated arteries (decided).** All major arteries are modelled (Captain). Where each sits decides the fix, so the treatment column is proposed from real casualty-care practice.

| Artery | Where | Treatment in the field (proposed) |
| --- | --- | --- |
| Common carotid (left, right) | Neck | Junctional: pack with hemostatic gauze and hold pressure |
| Subclavian (left, right) | Under the collarbone | Junctional: pack and hold pressure |
| Brachial | Upper arm | Tourniquet |
| Radial, ulnar | Forearm | Tourniquet or pressure bandage |
| Femoral | Thigh | Tourniquet; packing if high in the groin |
| Popliteal | Behind the knee | Tourniquet |
| Common iliac (left, right) | Pelvis | Junctional: pack and hold pressure, evacuate |
| Aorta | Chest and abdomen | Surgery kit (clamp with hemostats); IV fluids to buy time |
| Brachiocephalic trunk | Upper chest | Surgery kit; IV fluids to buy time |
| Renal (left, right) | Lower back, at the kidneys | Surgery kit; IV fluids to buy time |
| Pulmonary (left, right) | Inside the chest, to the lungs | Surgery kit; also a chest cavity wound |

Surgery kit (decided). Arterial bleeds can be stopped the old-fashioned way, by clamping them with hemostats from a surgery kit (Captain). It is the only field fix for arteries inside the torso. Kits come in three versions: common with 2 uses, uncommon with 3, rare with 5. Players and medics only, so regular AI squadmates can't use it (Captain). Proposed: about 20 s per clamp, and usable on limb and junctional arteries too when a tourniquet or packing isn't enough. A use can also treat penetrating chest trauma or a lung wound in place of a chest seal, but the wound can reopen (Captain). It has a 10% chance to reopen each time the casualty sprints, carries an extreme load, jumps or mantles (Captain). Reopening restarts the open chest wound and its tension pneumothorax risk.

**Blood loss effects (proposed starting values).** Effects start at 15% lost and grow in proportion to the loss up to 40%, where the soldier passes out. Call that growth s, running from 0 at 15% lost to 1 at 40% lost; each effect below is its full strength times s.

| Blood lost (of 6 L) | Litres left | Stage | Aim sway | Stamina recovery | Move speed | Vision |
| --- | --- | --- | --- | --- | --- | --- |
| 0 to 15% | 6.0 to 5.1 L | Compensating | Normal | Normal | Normal | Normal |
| 15 to 30% | 5.1 to 4.2 L | Early shock | Up to +60% | Down to 64% | Down to 88% | Colour fades slightly |
| 30 to 40% | 4.2 to 3.6 L | Severe shock | Up to +100% | Down to 40% | Down to 80%, no sprint from 30% | Tunnel vision, greying edges |
| 40 to 50% | 3.6 to 3.0 L | Unconscious |  |  |  | Out |
| 50% or more | under 3.0 L | Cardiac arrest |  |  |  | 10-minute window starts |

Pain, broken arms and concussion add their own sway on top, so a wounded, bleeding soldier stacks penalties.

AI uses exactly the same rules, so wounding an enemy and watching his buddy drag him is a real tactic. Enemies normally ignore unconscious foes and only dead-check bodies when clearing or assaulting through a position (Captain), so a downed friendly left in a room the enemy is pushing through is in real danger.

**The kit.** Ten items, two more drugs (below) and a defibrillator, each used up from the physical inventory.

| Item | Who | Time | Fixes |
| --- | --- | --- | --- |
| Tourniquet | Anyone | 4 s, or 6 s on yourself (one hand on your own arm) | Arterial limb bleed |
| Pressure bandage | Anyone | 5 s | Muscle wounds, grazes |
| Hemostatic gauze | Anyone | 8 s | Junctional bleed, converting a tourniquet |
| Vented chest seal | Anyone | 5 s | Open chest wound |
| Splint | Anyone | 8 s | Fracture |
| Morphine autoinjector | Anyone | 2 s | Pain: 0.5 off over 30 s; a second dose within 10 minutes risks overdose |
| NPA airway | Anyone | 3 s | Unconscious casualty's airway |
| Decompression needle | Medic | 5 s | Tension pneumothorax, instantly |
| IV or IO access, then a bag of saline or blood in 250, 500 or 1000 mL (separate items: no access, no bag). Saline and blood work identically and only look different (Captain) | Medic | 10 s for access, then the bag infuses over time at the 18 gauge base rate: 250 mL in 2.5 to 3 min, 500 mL in 4 to 5 min, 1000 mL in 7 to 8 min | Blood volume |
| Epinephrine | Medic | 2 s | Forces a wake-up roll; part of CPR |

**IV gauge sets the flow (decided).** IVs come in 10, 12, 14, 16, 18 and 20 gauge; the larger the catheter (lower number), the faster fluid goes in (Captain). The bag times above are for an 18 gauge. The multipliers below are proposed from approximate real gravity flow rates and need checking before they are tuned.

| Gauge | Flow vs 18 gauge | 1000 mL bag (approx.) | Time to place | Pain added | How common |
| --- | --- | --- | --- | --- | --- |
| 10 | 5x | about 1.5 min | 22 s | +0.20 | Very rare |
| 12 | 4x | about 2 min | 18 s | +0.15 | Rare |
| 14 | 3x | about 2.5 min | 15 s | +0.12 | Uncommon |
| 16 | 2x | about 4 min | 12 s | +0.08 | Uncommon |
| 18 (base) | 1x | 7 to 8 min | 10 s | +0.05 | Common |
| 20 | 0.6x | about 12 to 13 min | 8 s | +0.02 | Common |

**The trade-off (decided).** Bigger IVs are rarer to find, take longer to place and add a bit of pain to the casualty (Captain). That extra pain can keep someone over the knockout threshold longer or cost an extra morphine dose, so a medic has to weigh speed against both. The flow, time, pain and rarity values are proposed starting points.

**IO access (decided).** An IO flows at the 18 gauge rate by default and at the 16 gauge rate (2x) with a pressure bag (Captain). In real life IO is usually slower than a good IV; its advantage is placement, so the game leans on that.

- **Placement (proposed):** about 5 s, and it always works, even in deep shock.
- **IVs in shock (proposed):** as blood loss rises and veins collapse, IVs take longer to place and can fail, so IO becomes the pick for a casualty in severe shock and an IV the pick when there is time.
- **Pressure bag:** a new kit item that works on IVs too (Captain). With good veins it speeds an IV up (proposed: 2x the gauge rate, like IO). Veins start collapsing at 37% blood lost (Captain), and from then the bag becomes necessary: without it a collapsed-vein IV slows down (proposed: half its gauge rate), and with it the IV runs at 1.25x its gauge rate (Captain).

This also eases the cardiac-arrest timing: with a 14 gauge, the 600 mL needed to get back to the CPR threshold goes in in under 2 minutes instead of about 5.

Two more for other injuries: a burn dressing and a hypothermia blanket (5 s).

**Drugs (decided).** Four drugs and no more: epinephrine, morphine, adenosine and atropine (Captain). There are no blood types and no heart rhythms to read. Roles for the two new ones (decided), using heart rate only, which a medic reads as a pulse:

| Drug | Who | Time | Proposed use |
| --- | --- | --- | --- |
| Atropine | Medic | 2 s | Raises a heart rate that is too slow, for example after a morphine overdose or in deep shock |
| Adenosine | Medic | 2 s | Slows a heart rate that is racing, for example after too much epinephrine |

That gives morphine and epinephrine a real cost: too much of either pushes the heart rate somewhere a medic has to fix.

**Defibrillator (decided).** A medic can defibrillate a casualty in cardiac arrest, alongside CPR and drugs. It shocks without anyone reading a heart rhythm. Like CPR, it does nothing until blood volume is restored. Players and medics only (Captain). Proposed: about 5 s per shock, raising the chance that the heart restarts on that cycle.

**Other damage.** Most of it reuses the bleeding, fracture and pain rules above.

| Source | Effect | Treatment |
| --- | --- | --- |
| Fragments (grenades, shells, IEDs) | 3 to 8 small wounds across the body, sometimes one arterial or chest wound | Same items as bullets; the work is the number of wounds |
| Overpressure (about 5 m from a frag, doubled indoors or against a wall) | Ringing ears and muffled audio for 20 to 60 s, a concussion check, a small chance of blast lung | Time; blast lung acts like a slow chest injury and needs evacuation |
| Thrown by a big charge, or a fall | No damage under about 3 m; 3 to 6 m gives leg pain and a 30 to 70% fracture chance; above about 10 m likely fatal | As fractures |
| Concussion (helmet stops a round, with a chance by round class from Impact damage below, or a blast in range) | Possible knockout for 5 to 20 s, then 60 s of blur, sway and slow turning; a second one in the same fight lasts twice as long | Nothing in the field; it has to pass |
| Unprotected head hit past the helmet | Fatal | None |
| Burns (fire, burning vehicles, close blasts) | Under 20% of the body: pain only. Over 20%: slow fluid loss like blood loss | IV fluids and evacuation; a burn dressing takes off some pain |
| Hypothermia | 30% or more of blood lost and lying still for over 5 minutes: bleeding 25% faster | Hypothermia blanket |
| Flashbangs and indoor gunfire | Flashbang whiteout and deafness for 3 to 6 s by distance and facing; muffled audio for about 30 s after sustained indoor fire | Time; electronic ear protection prevents it |
| Vehicle crashes, rifle butts, melee | Bruising (pain, no bleeding), fractures, cuts | Reuse the muscle-wound and bruise rules |

**Impact (shock) damage (decided).** Rounds that armor stops still hit hard. Like DayZ's shock damage but much smaller, a stopped round adds impact to that body region: bruising and other non-lethal injury behind plates and under helmets (Captain). Impact causes pain and can knock someone out, but it kills only where the same hit would kill in real life. Blasts and falls feed the same impact.

| Round stopped by | Pistol | Intermediate rifle | Full-power rifle (.308) |
| --- | --- | --- | --- |
| Plate (torso) | Pain +0.05 | Pain +0.15, brief stagger | Pain +0.3, winded (stamina emptied for a few seconds) |
| Helmet | Pain +0.15, 10% concussion chance | Pain +0.3, 40% concussion chance | Pain +0.45, 80% concussion chance |

These are proposed starting values. With them, two .308 hits on a helmet from a distance add 0.9 pain, which is a knockout at full blood, as Captain described. Impact fades over about 5 minutes, so repeated hits in one fight stack.

- **When impact can kill (decided):** only for injuries that are fatal in reality, such as a rifle round stopped by a helmet causing a fatal head injury, or a blast or fall already lethal under the rules above. A helmet stop can be fatal out to about 200 m, depending on the cartridge and its ballistics (Captain). A plate stop alone never kills.
- **Cracked ribs (decided):** a round stopped by a plate can crack a rib (pain, slower stamina recovery), but only within 30 m for pistol rounds, 100 m for intermediate rifle rounds and 200 m for full-power rifle rounds (Captain).

  **Ballistics (decided):** ammunition uses ACE3's ballistics values (muzzle velocity, ballistic coefficient, drag), so a round's energy at any range comes from that data, to be checked in game (Captain).

* **Armor first.** A round stopped by a voxel plate or helmet makes no wound; one that gets through a hole wounds the body part behind it.
* **Medics.** One medic per fire team carries the needle, IV and epinephrine; everyone else carries the rest of the kit.
* **Fits the squad decisions.** Care follows the real casualty-care order: under fire, smoke, drag to cover and tourniquet; once safe, airway, chest seal, IV and splint; then carry the casualty with the squad or evacuate by helicopter.
* **Left out:** blood types, cardiac rhythms, surgery beyond the hemostat surgery kit, stitching and every drug beyond the four above, plus drowning, infection, delayed blast injuries and rope burns. They add actions without adding decisions.

### NPC squad and roster (settled)

- Squadmates have their own armor slots and pack volume, pick items up themselves and use their own kit mid-fight, such as patching the player.
- They are not a storage bank: how much they carry for the player depends on relationship, experience and stats that grow each deployment.
- Each squadmate owns their gear, history and injuries; the wounded sit out missions.
- **MIA.** A downed AI squadmate not extracted when the team leaves the area is missing in action, and a recovery mission opens that may be hard or fail. This applies to AI squadmates only; players respawn. AI captured during a mission, for example after the players die, can be rescued back into the squad; otherwise they become POWs and go MIA. Redeploying AI is limited by manpower and gear availability (Captain). The repo's locked rule differs (permadeath if left at extraction); see Conflicts with the build.

**Decided since the first draft:**

- **Player role.** The player is a commander who fights alongside the squad and gives it orders.
- **8-slot squad.** A squad is 8 strong. Up to 4 human players take slots and AI fills the rest: 1 player leads 7 AI, 4 players share 4 AI. AI squadmates are recruited from a rotating hiring pool of contractors, each with a role, skills and wage demands, and veterans cost more; there is no fixed starting squad. Squadmates improve with experience: surviving missions raises their skills (aim, nerve, medical and so on) and their wage, so losing a veteran hurts. Serious wounds carry over: a squadmate with fractures, surgery or heavy blood loss sits out some campaign days to recover, and treatment costs money. A severely injured player sits out the same way and must swap to an available NPC squadmate; if none is available, one is provided free. Each player has one main character and plays an NPC squadmate only while that character recovers; there is no free swapping between missions (Captain, mission brainstorm).
- **Battle buddies everywhere.** All AI, the player's squad and enemies alike, works in battle-buddy pairs and uses real-world infantry tactics, including grenades, flashbangs and smoke. LAMBS Danger.fsm and VCOM 3.4.0 for Arma are the behavior references. Detection uses realistic senses: enemies spot by sight and sound, affected by distance, light, camo, stance, movement speed, foliage and weather, and suspicion builds before a full alert, giving a moment to freeze or break contact (Captain, mission brainstorm).
- **Downed friendlies.** Out of combat, a battle buddy picks up and carries the downed friendly and follows the squad leader; there is no exfil zone for casualties. In a firefight, a squadmate may throw smoke, drag the downed friendly to cover, then revive them or keep them safe.
- **Medical.** ACE3 medical plus KAT advanced medical is the reference for injuries and treatment, and damage uses wounds, bleeding and pain instead of hitpoints (see Damage and medical).

**How the build will do it.** The repo's phase 3 proposal (`docs/squad_design.md`) makes a squadmate a shared `Soldier` body driven by a `SquadAI` node that uses the same host-validated actions as players, with utility-scored intents (Follow, Hold, Move to, Take cover, Engage, Revive, Heal self, Reload, Resupply, Retreat) and one lead player whose most recent order wins. It is one shared squad, and enemies reuse the same body and AI. It was written before the 8-slot squad, battle buddies and downed-carry decisions, so it still needs those (see Conflicts with the build).

### Vehicles (proposal)

Vehicles are the campaign's "mech": the big, modular, damageable, expensive asset that gives progression a spine. They are also a rolling stash whose cargo capacity caps salvage profit, and a single point of failure: if it burns, everything inside goes with it. Ground vehicles can be driven by players or AI; aircraft are AI-flown only, for transport and fire support (repo, locked).

**First vehicles (decided).** The first vehicles to be modeled are the UH-60 Black Hawk, AH-1Z Viper, AAV, MRAP, M2 Bradley, M1 Abrams and technicals, all in the voxel art style (Captain). Every vehicle is rebuilt faithfully from its real counterpart, and technicals cover the real-world variants commonly seen in the Middle East (Captain). Proposed technical set: Toyota Hilux and Land Cruiser pickups mounting a DShK, ZPU-1 or ZPU-2, ZU-23-2, SPG-9 or B-10 recoilless rifle, or rocket pods. The Black Hawk and AAV are player-faction supports, and technicals are enemy vehicles. Open: who fields the AH-1Z, MRAPs, Bradley and Abrams, and how. Possibilities include an attack-helicopter support for the player faction, and MRAPs as ground transport.

**Vehicle armor (decided).** Vehicle armor is immune to small-caliber rounds. Only 7.62x54R and larger can penetrate or disable a vehicle (Captain; their message said "762x4r", read as 7.62x54R). Open: whether unarmored parts, such as a technical's cab or a helicopter's glass, follow the same rule.

**Anti-armor weapons (decided).** Anti-armor weapons work like their real counterparts, with results that depend on the type of round (Captain). Proposed round types: HEAT (shaped charge) penetrates armor; tandem HEAT defeats reactive armor; HE and HEDP are for soft vehicles, structures and infantry; thermobaric is for buildings and bunkers; top-attack guided missiles, like the Javelin, strike the thin roof armor. The launchers are the AT4, RPG-7 (PG-7V HEAT and OG-7V frag), Javelin, MAAWS, NLAW and SMAW (Captain).

### Factions and world (settled, with proposals marked)

- **Reputation buys troops.** Allied factions send troops into the player's AO in warzones. They work around the player's objectives, assist through a support menu and keep enemies clear of the AO.
- **Player-built faction.** With enough reputation the player builds their own faction from scratch.
- **Live conflict.** The world has 3 factions with reputation tiers (placeholder data in the repo); two of them fight in a given AO, and that fight keeps simulating, and the player can tilt it by sabotaging supply lines, escorting convoys or looting the aftermath. Decided (Captain): the world is persistent, so damage is repaired and positions are reoccupied over campaign time, and between missions factions run simulated operations against each other that move the front. The war posts matching contracts, such as retaking a lost outpost or raiding ahead of an offensive. Sides are locked: taking work from one faction locks you out of its enemies' contracts for a while (Captain).
- **Persistence.** Cleared outposts stay cleared, wrecks stay put, and field caches survive between contracts.
- **Factions read your gear (proposal).** A captured uniform gets you past a checkpoint until someone notices your rifle.

### Procedural areas

Terrain can be procedural; combat spaces are not. Areas are assembled from hand-built modules (compounds, blocks, outposts) with faction positions layered on top. Variety comes from objectives, factions, time of day, weather and persistent state, not layout shuffling.

### Tension without PvP

A reinforcement timer that runs from the start of each contract (repo, locked), escalating faction response, bodies that can only be scavenged for a limited time, and scarcity that makes every magazine count. A safety floor (cheap low-risk contracts, a faction loan, gear recovery missions) stops a bad run from becoming a death spiral.

## Player faction supports (decided)

The player's own faction backs the squad with four supports: Blackhawk resupply, Blackhawk transport, AAVs and Blackhawk extraction, all called from the command menu and run by AI. That matches the repo's locked rule that aircraft are AI-flown only. In a hot zone on the coast, an LHD sits offshore on the map and every support launches from it live. Inland, a FOB plays the same role (Captain). The LHD and FOB are the company's home base: a mobile HQ that moves between regions, with an armory, medbay and hiring board that are upgraded over time (Captain). In hot zones, supports are live and dynamic: weather and terrain decide what can fly or drive (storms ground helicopters, AAVs can't work mountains), and the price of a call going wrong is losing the asset itself. A lost asset such as a helicopter is gone for the rest of that op and has to be replaced afterward (Captain).

| Support | Where | Vehicle | Lands or delivers at | What it does |
| --- | --- | --- | --- | --- |
| Helicopter resupply | Not limited by Captain | Blackhawk | A designated map grid coordinate, or a thrown green or yellow smoke | Lands and drops off a supply pallet |
| Helicopter transport | Hot zones only | Blackhawk, from the LHD on the coast or the FOB inland | A grid coordinate, or a green or blue smoke; with neither, it loiters near the players, avoiding enemy fire, until it sees one | Moves the players and squad, working like live transport support in Arma 3 |
| AAV | Hot zones (deploys from the LHD on the coast; proposed: from the FOB inland) | AAV amphibious vehicle | Drives in from the LHD or FOB | Transport, and a support the player can command from the command menu |
| Helicopter extraction | Not limited by Captain | Blackhawk | A grid coordinate or a purple smoke, or near either if the ground there can't take a landing | Evacuates HVTs, loot and items the players and squad AI deposit |

&#91;embedded content: helicopter call-in · grid or smoke, loiter until marked\]

Every helicopter support follows the same call-in: a grid coordinate sends it straight in, and without one it waits for a friendly smoke of the right colour. Each support has its own colours: green or yellow for resupply, green or blue for transport, purple for extraction. Extraction also sets down nearby when the marked spot itself is a bad landing area (terrain or obstacles); enemy presence or fire does not move it.

**How it fits the build.**

- Aircraft are AI-flown only, and ground vehicles can be driven by players or AI (README, locked), so AI-flown Blackhawks and commandable AAVs both fit. They belong to roadmap phase 5, ground vehicles and aircraft.
- Coloured smoke grenades (green, yellow, blue, purple) need entries in `data/items.json`, which already has grenades.
- Grid coordinates need a map with a grid overlay, which the build does not have yet.
- Helicopter extraction changes the haul-out step: loot still has to be physically carried to the deposit point, but it no longer has to fit in packs and the vehicle for the whole trip home. It also ties into the repo's rule for squadmates left at extraction (see Conflicts with the build).

## Controls and feel

The shooter should feel deliberate and grounded, and handling gear should be fast enough that it never becomes the thing players fight. These are proposed defaults, not decisions from the handoff.

- **First person, full body.** The player sees their own rig, plates and pack, which keeps readability and tactile fantasy in the camera.
- **Quick actions bound to slots.** Reload pulls the next magazine from a rig slot; medical and grenades come from their own slots. No dragging magazines into containers mid-fight.
- **Pack interior is a slower, deliberate view.** Opening a pack takes time and leaves you exposed, which is where the tension of looting comes from.
- **Inspect and attach.** Items can be picked up, turned over and attached to slots directly in the world.
- **Arma 3-style command interface (decided).** Instead of keybound orders, F1 to F12 select squadmates and open command menus as in Arma 3. Command and support-call menus are navigated with middle-mouse clicks, or with the 1 to 9 keys for players who don't want to click. The player is the squad's commander, so orders cover the whole 8-slot squad and its battle-buddy pairs, and the support calls (resupply, transport, AAVs, extraction, allied troops) live in the same menus.
- **Grenades on G (decided).** G throws the selected grenade; holding Left Shift and pressing G cycles grenade type (frag, flashbang, the smoke colours).
- **Drop on Alt+G (decided).** Alt+G drops the carried bulky item or active weapon, which frees G for grenades and keeps H as the medical-item key (Captain).
- **Movement and weapon keys (decided).** F changes fire mode, X crouches, Z goes prone, and Q and E lean left and right (Captain). Hold Q or E to lean; double-tap either to stay leaned, and tap it again to return to normal (Captain). C mounts the weapon on a surface in front of you, such as a wall, sill or vehicle, for more stability and recoil control (Captain). Proposed: mounting cuts sway and recoil by about half, and moving or changing stance unmounts.
- **Arma 3 stance system (decided).** Ctrl+W and Ctrl+S step your stance up and down in fine steps between standing, crouching and prone, and Ctrl+A and Ctrl+D shift it to the side, as in Arma 3, so you can match cover and fighting positions (Captain). Proposed: three heights each for standing and crouching, and side stances for standing, crouching and prone (prone rolled to one side).
- **ACE-style interaction (decided).** Interacting with objects in the world works like ACE3's interaction system in Arma 3 (Captain). Hold the interact key and look at an object, vehicle or person to show its action points, move the cursor onto one to open a radial menu of actions, and release to pick the action. A separate self-interact key opens the same kind of menu for your own body and gear. Keys are ACE's defaults, Left Windows to interact and Ctrl+Left Windows to self-interact, rebindable (Captain approved). Treating another unit, loading cargo, opening doors, picking up and attaching items, and handing gear to a squadmate all go through these menus.
- **Weight you can feel (decided).** Movement has weight (Captain): the body accelerates and stops over a short distance, carries momentum into turns and stance changes, and settles with a little weapon sway after a stop. Load makes all of that heavier and changes speed, stamina and noise, so a full haul-out is felt in the hands, not read off a number. Proposed: an unloaded soldier reaches a jog in about 0.3 s, and a heavy load roughly doubles both start and stop times.

## Roles, HUD, weapons, economy and world

These were settled for the production handoff on 2026-10-10. Captain set the medic rule and player roles, and the rest were Claude's defaults that Captain accepted.

- **Medics and roles.** Every fire team has one medic (Captain). Players pick their own role (Captain). Proposed: the 8-slot squad is two fire teams of four, roles are team leader, medic, autorifleman, grenadier, marksman and rifleman, a role sets the starting kit, and AI squadmates fill whatever roles the players leave open.
- **HUD.** Minimal, as in Arma with ACE: no health bar and no ammo counter. You check a magazine by feel, read wounds through self-interaction, and find your position on the map.
- **Weapons.** Real-world guns with modular attachments: optics, lights, lasers, suppressors and grips. Ammunition uses ACE3's ballistics values.
- **Money.** Contracts pay cash, and cash buys gear, repairs, medical supplies and support calls. It also pays AI squadmates' wages, hired from a rotating pool where veterans cost more (Captain). Salvage works both ways: the squad keeps whatever it carries or extracts, and the negotiated salvage share also lets it claim items left in the field after the mission, like MW5's salvage picks (Captain).
- **Enemies.** Enemy factions field infantry that uses the same battle-buddy tactics as the squad, plus technicals and light vehicles. Depending on their region, enemy factions use Chinese, Russian, Iranian or terrorist-style gear (Captain).
- **Factions and allies.** The player faction is a PMC company. Friendly factions include the USA, Great Britain and Canada, and depending on reputation, players can buy gear and vehicles from those allies (Captain). Expanded (Captain): the game gets a faction for every major real-world power, from the US to Russia, including Ukraine, Poland and Switzerland, each with its modern-day alliances, played out on procedurally generated worldspaces inspired by the modern world. Each faction fields the real-world vehicles it is known for, modeled from web reference photos. Two more regional worldspaces are planned, one for Israel and one for Palestine/Iran, plus one for Middle East terrorist factions modeled on groups like Hamas and al-Qaeda, who are the main enemy of the early game. Worldspaces are the final concern, so they come last. The faction set is being drafted in the vehicle model refinement thread and lands here when ready. Open: how this replaces the repo's three-faction placeholder data, and which reputation tier unlocks what.
- **Time and weather.** A day and night cycle with weather, and night-vision goggles as gear.
- **Difficulty.** One realistic difficulty, with optional assists for co-op newcomers.
- **Zone regions.** Contract zones and hot zones share the same map regions.

## Scope: core versus stretch

Scope is the biggest risk in the handoff: physical inventory, vehicles, squad AI, faction simulation and procedural worlds are each studio-sized. Captain decided the shooter and the campaign are equally important, so neither gets cut down to a shallow layer. The split below folds in the decisions since the first draft; the rest is still a proposed default.

| System | Core for the first playable campaign | Stretch |
| --- | --- | --- |
| Physical inventory | Body slots and plate pockets, litre volume, two-handed bulky items (built) | Free 3D placement inside packs, bag-as-collider routes |
| NPC squad | 8-slot squad in battle-buddy pairs, own kit, carry trust, downed-friendly carry and drag, ACE3/KAT-style injuries, MIA | Deep personalities, permadeath rules, squadmate perks trees |
| Vehicles | 1 drivable ground vehicle with cargo, damage and repair | Several vehicle classes, modular customization, AI-flown aircraft |
| Factions | 3 factions, two fighting in each AO, reputation unlocking a simple support menu | Player-built faction, territory that shifts between missions |
| World | 1 region, 6 to 10 hand-built modules, persistent cleared state and wrecks | More regions, field caches, gear-based disguise |
| Contracts | Contract zones with 3 objective types and pay vs salvage terms, plus 1 hot zone | More hot zones, recovery missions with branching outcomes, contract chains |
| Base | Walkable hub: armory, motor pool, medbay | Base upgrades and faction HQ |
| Co-op | Up to 4 players taking squad slots from the AI; listen server with the host authoritative (built) | Not defined yet |

Co-op is now core, which shapes everything else: retrofitting networking onto physics-based inventory is far harder than building with it in mind.

## Engine: Godot (decided)

**Decision: Godot.** Captain chose Godot after the first draft recommended Unity. The build runs on Godot 4.7.2 with Zylann's Voxel Tools 1.7 built into the editor, GDScript and Jolt physics, with ENet co-op as a listen server (repo README). The comparison stays here as a record of where Godot needs extra work.

| Need from the design | Unity | Godot 4 |
| --- | --- | --- |
| Large explorable terrain | Built-in terrain system and streaming tools | Needs community add-ons for large terrain |
| Many AI units (squad plus two factions) | NavMesh tooling, mature behavior tree assets, DOTS for scale if needed | Built-in navigation works, fewer proven tools at large unit counts |
| Vehicles and physical items | PhysX plus established vehicle physics assets | Jolt physics is solid; fewer ready-made vehicle solutions |
| Co-op networking | Several mature options (Netcode for GameObjects, Fish-Networking, Photon) | High-level multiplayer API, smaller ecosystem |
| Asset ecosystem for a small team | Very large: weapons, characters, inventory, AI | Small, growing |
| Cost and licensing | Free tier, paid seats above a revenue threshold | Free and open source (MIT) |

The comparison is from general knowledge and was not checked against current versions. With Godot, the rows to budget for are many AI units at once (8-slot squads plus two fighting factions, all in battle-buddy pairs), vehicle physics and co-op networking for up to 4 players.

## Roadmap phases and open questions

These are the repo's roadmap phases, so the doc and the build share one numbering; design items from this doc are mapped onto them. The riskiest system, squad AI, is next.

1. **Foundation (v0.1.0, done).** Gray-box compound, first-person co-op player, litre inventory, voxel plates, destructible walls, zone save.
2. **Inventory depth (done, unreleased).** Ammo and reloading, inventory screen, item state that travels with the item, medical items, downed and revive.
3. **Squad prototype (next, highest risk).** Built per `docs/squad_design.md`, starting with one squadmate. From this doc it also needs battle-buddy pairs, grenades, flashbangs and smoke, downed-friendly carry and drag, and the 8-slot squad as the target. Proposed: move damage from hitpoints to the wound model here, since squadmates have to treat each other with it. Passes when squadmates rarely die to bad pathing.
4. **Mission loop.** Contracts, reinforcement timer, extraction, salvage share, persistent zone graph. Contract zones land here; the first hot zone follows once one contract zone plays well.
5. **Ground vehicles.** Drivable, modular damage, cargo as a rolling stash; aircraft as AI-flown transport and fire support, including the player faction's Blackhawk supports, AAVs, AH-1Zs, MRAPs, and the LHD for coastal hot zones and the FOB inland.
6. **Factions.** Territory, reputation tiers, dynamic events, and the allied-troop support menu.
7. **Vertical slice and art.** Voxel character and gear models, voxel import pipeline, polish.

The player-built faction stays a late-game stretch goal after phase 7.

**Open questions.** Player role, the shooter-versus-campaign balance, co-op size and the engine are now decided and folded in above. The hot-zone questions come first because they shape the vertical slice and campaign loop.

- [ ] **Hot zone flow:** decided. The squad can hold several of the faction's contracts at once, resupply by helicopter, and bank loot mid-zone by sending it out on an extraction.
- [ ] **Hot zone exit:** decided. A hot zone ends when the squad extracts, and unfinished contracts lapse with a small reputation hit.
- [ ] **Zone availability:** hot zones need no reputation minimum but are considerably harder than contract zones, which only offer up to medium-tier weapons, armor and gear as loot and salvage, scaled by difficulty (Captain). Still open: do contract zones and hot zones share the same map regions?
- [ ] **Player death** (decided, Captain): a player who dies respawns in default kit: an M4, 2 spare mags plus 90 loose spare rounds (proposed reading), 1 smoke and 1 frag. Their gear stays where they died, with a map marker to guide them back to recover it. Respawns are limited: the squad shares one pool per deployment, with 4 free in a contract zone and 8 in a hot zone, and more must be bought after that (Captain). The build currently respawns players at the gate with full gear, so this changes it.
- [ ] **World simulation depth:** decided. Faction territory shifts between missions only.
- [ ] **Reputation and troops:** reputation tiers, troop types, and what limits the support menu. Partly decided: allies are the USA, Great Britain and Canada, and reputation with them unlocks buying their gear and vehicles (Captain).
- [ ] **Player-built faction:** what it involves and whether it replaces or sits beside contracts.
- [ ] **Team size:** decided. Captain and Claude, plus a teammate and their Claude (Captain).

* [ ] **Medical depth:** decided as a middle ground (Captain); the values above are starting points to tune in playtests.

- [ ] **Body map:** organs decided (lungs, heart, brain, arm and leg bones, tissue, chest cavity wounds). Arteries decided (see Simulated arteries). Veins: the big ones (jugular, subclavian, femoral, vena cava). Surgery kit: players and medics only. Breathing and alveolar efficiency are simulated. Still open: surgery kit time, and the exact closeness and cavitation curve (how fast bleeding falls off with distance from the wound channel).

* [ ] **IV gauge trade-off:** decided: rarer, slower to place and more painful (Captain). IO flow is decided too (18 gauge rate, 16 gauge with a pressure bag). Pressure bags work on IVs too (decided).

**Supports:**

- [ ] **Unlock:** decided. Supports are available from the start of the campaign.
- [ ] **Shared green smoke:** decided. Green marks both resupply and transport; if both are inbound, the one called first takes the green smoke.
- [ ] **Without an LHD:** decided. Inland zones have a FOB that supports launch from, the way they launch from the LHD on the coast (Captain). Proposed: AAVs deploy from the FOB too.
- [ ] **Where resupply and extraction work:** decided. Resupply and extraction work in every zone; transport is hot zones only.
- [ ] **Limits:** decided. Each support call costs money and has a cooldown.
- [ ] **Losses:** decided. Blackhawks and AAVs can be shot down or destroyed, and whatever cargo and passengers they carry are lost with them.
- [ ] **Extraction and the left-behind rule:** decided. A helicopter extraction counts as the extraction for the AI squadmate MIA rule.
- [ ] **Banking loot:** decided. Loot evacuated mid-hot-zone banks immediately.

* [ ] **Safe to land:** unsafe means the landing area only, not enemy presence or fire (Captain). Decided: a slope over 15 degrees, water, buildings or trees make a spot unsafe, and the helicopter sets down within 100 m of the marker.

## Conflicts with the build

These are the places where this doc, the handoff or Captain's later decisions disagree with the repo (README locked decisions and `docs/squad_design.md`, read 2026-10-09). Each needs Captain's call before phase 3 locks it into code.

| Topic | Doc and decisions | Repo | Proposed resolution |
| --- | --- | --- | --- |
| Damage model | No hitpoints: wounds per body part, bleeding, pain, unconsciousness and cardiac arrest, like ACE3 and KAT (Captain) | `Vitals` uses HP: kits heal set amounts (IFAK +35 HP, trauma kit +70 HP), revive brings you back at 25 or 50 HP, headshots do 3x damage, a flat 60 s bleed-out | Decided (Captain): replace HP in `Vitals` with the wound model during phase 3; turn IFAK and trauma kit into bandages, tourniquets and the rest; keep `_server_use_medical` so every treatment uses a real item |
| Downed squadmate left behind | MIA, with a recovery mission that may fail (handoff, settled) | Permadeath if bled out or left at extraction (README, locked) | Decided (Captain), AI squadmates only: bleeding out is permadeath, left behind alive is MIA with a recovery mission. Players respawn instead (see Player death) |
| Squad size | 8 slots, AI fills what humans don't (Captain) | `squad_design.md` recommends 2 squadmates | Decided (Captain): phase 3 starts with one squadmate and scales to 8; `squad_design.md` should name 8 as the target |
| AI tactics | Battle-buddy pairs and real infantry tactics for all AI, with grenades, flashbangs and smoke (Captain) | Intents have no buddy pairing or throwables | Add buddy pairing and a Throw intent to decision 3 of `squad_design.md` |
| Downed friendlies | Out of combat a buddy carries them and follows the leader; in a fight, smoke and drag to cover (Captain) | Revive is the only downed behavior | Add Carry and Drag intents, and treatment intents for the wound model |
| Inventory unit | cSCU (handoff) | Litres (README, locked and built) | Keep litres; this doc now uses litres |
| Editor build | Standard Voxel Tools 1.7 editor (Captain) | README asks for the standard Voxel Tools 1.7 editor build | Resolved: the README is already right |
| G key and 1-9 keys | G throws grenades, Shift+G cycles type; 1-9 pick menu entries (Captain) | G drops the carried bulky item or active weapon; 1 and 2 switch primary and sidearm (README controls) | Decided (Captain): drop moves to Alt+G, and H stays the medical-item key. Decided (Captain): 1-9 pick menu entries only while a command menu is open, otherwise switch weapons |
| Armor plates | Plates act like real plates: ceramic cracks around hits, weakens with consecutive hits in a small area and can be destroyed; rounds and armor use NIJ ratings (Captain) | Hits chip voxels and only a hole lets rounds through (README, locked) | Decided (Captain): keep voxel chips as the visual; add NIJ-style ratings for rounds and armor, crack zones and plate integrity |

Resolved in this doc to match the repo: 3 factions, the reinforcement timer, the zone-graph map, AI-flown aircraft, the listen-server co-op model and the roadmap phase numbering.
