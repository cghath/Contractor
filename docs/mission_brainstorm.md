# Contractor Mission Brainstorm

Oct 10, 2026 · @Captain

Working brainstorm for roadmap phase 4 (missions). Nothing here is settled unless marked
DECIDED. Settled items get passed to the design doc.

Exported from the claude.ai doc (https://claude.ai/code/artifact/504b59c6-2729-45a1-8709-6fa39892c701),
pasted by Captain on 2026-10-11.

## Already decided

- Zone contracts: contract-to-contract missions. Loot and salvage capped at medium tier, scaled by difficulty.
- Hot zones: a larger live deployment area holding several contracts from one faction, raid-like, no
  reputation minimum, considerably harder. A hot zone ends at extraction.
- Supports: helicopter resupply, helicopter transport (hot zones only), AAVs, helicopter extraction of
  HVTs and loot. Coastal zones stage from an LHD, inland zones from a FOB.
- MIA recovery missions for AI squadmates left behind alive.

## Scale ladder (proposal)

| Tier | Area | Length | Objectives | Opposition |
|---|---|---|---|---|
| Zone contract | about 2 to 4 km² | 40 to 90 min | 1 primary, 0 to 2 optional | about a platoon (20 to 40), small QRF |
| Hot zone | about 8 to 16 km² | 2 to 4 hours, player chooses when to extract | 3 to 6 contracts live at once, taken in any order | a reinforced company spread across the zone, with QRFs and patrols that react to noise |
| Campaign operation (idea) | several deployments | several campaign days | an arc of linked contracts with one payoff | a faction's whole front |

## Mission types

**Direct action**
- Raid: destroy a cache, AA site, comms tower or mortar team.
- HVT kill: confirm the kill by bagging a physical item (dog tags, phone).
- HVT capture: restrain, carry or march them to helicopter extraction. They can be wounded and bleed out like anyone else.
- Compound assault: breach and clear, using voxel destruction.
- Sabotage: plant charges on a bridge, fuel depot or vehicle park.
- Convoy ambush: pick the ground, set up, spring it.

**Recovery**
- Hostage or POW rescue.
- MIA squadmate recovery (decided).
- Crash site: reach a downed aircraft, recover the black box or crew before the enemy does.
- Asset recovery: physical cargo (crates, a vehicle, a weapon system) that is heavy and slows the squad.
- Intel grab: laptops, drives and documents as real inventory items.

**Recon**
- Recon and mark: find and report positions without being detected.
- Overwatch: cover an allied element moving through.
- Forward observer: spot for an artillery or air strike.

**Defensive**
- Hold: defend a position or person until relief arrives.
- Escort: VIP or convoy escort across the zone.

**Hot zone only**
- Dynamic events while deployed: enemy QRF, enemy air, a rival contractor team hunting the same
  objective, hostile faction bounty hunters hunting the squad, a target that relocates.

## Objective and payment structure

- Primary objective pays base; optional objectives pay bonuses.
- MW5-style contract negotiation (idea): trade pay against salvage share and support budget before accepting.
- Penalties (idea): civilian casualties, collateral damage, lost squadmates, failed primary.
- Early extraction always possible, with reduced pay.

## Modifiers

- Night, fog, rain.
- Time limit.
- Enemy armor or air present.
- AA threat that blocks some helicopter supports.
- Radio jamming that cuts support calls until a jammer is destroyed.
- Civilians present.
- Enemy quality tier: militia, rival PMC, conventional army, special forces.

## Decided by Captain (2026-10-10)

- **DECIDED Scale ladder:** map areas doubled from the first proposal. Zone contract about 2 to 4 km² and
  40 to 90 min, hot zone about 8 to 16 km² and 2 to 4 hours (lengths doubled to match).
- **DECIDED** MW5-style negotiation before each contract, trading pay against salvage share and support budget.
- **DECIDED** Civilians are on the map, with penalties for hitting them.
- **DECIDED** Rival contractor teams are a recurring enemy. Hostile factions can also send bounty hunters after the player.
- **DECIDED** The campaign-operation tier is late game, part of the player-built faction.
- **DECIDED Bounty hunters:** angering a faction builds heat, and high heat brings generic hunter teams into
  missions near that faction's territory. At the top end, persistent named hunter squads appear that
  remember the player and come back.
- **DECIDED Civilian casualties** (only those caused by players or their AI squadmates, never deaths caused
  by other factions): each one costs a fine from pay plus reputation with the hiring faction and the
  locals. Past a threshold the contract is voided and pays nothing (threshold: 8 civilians).
- **DECIDED Contract sources:** a public contract board per region for regular jobs, plus faction contacts
  (fixers) for special and high-pay jobs that unlock with better relationships.
- **DECIDED Squad wipe:** players respawn at the LHD or FOB in default kit and can push back in while the
  contract runs. Respawns are limited. Redeploying AI squadmates depends on available manpower and gear.
  AI captured during a mission (for example, after the players go down) can be rescued back into the
  squad during that mission; otherwise they become POWs and go MIA, with a recovery contract.
- **DECIDED Respawn limits:** the whole squad shares a free pool of 4 respawns on a zone contract and 8 in
  a hot zone. After the pool is spent, each further respawn is bought from the support budget
  (proposed: cost rises with each one).
- **DECIDED Time limits:** only some contracts have a clock (hostage, crash site, HVT); the rest end at
  extraction. Timers are forgiving for now. Proposed: about twice the expected completion time.
- **DECIDED HVTs:** friendly HVTs (VIPs, hostages) cooperate and follow the squad. Hostile HVTs resist: they
  try to run, shout to expose the squad, and fight back. Zip cuffs stop the resisting. Any HVT can be
  carried or loaded into a vehicle passenger seat, and can be hit or bleed out like anyone else.
- **DECIDED Intel:** laptops, phones and documents are physical inventory items. Bringing them back reveals
  new contracts, caches or HVT locations, or they can be sold to other factions for money and rep at the
  risk of angering the original client. Intel drops in the world as well as on intel objectives: on
  enemy squad leaders and officers, and in outposts and military checkpoints. Reference: the Arma 3
  Sefrou-Ramal persistent recovery mission.
- **DECIDED Persistent world:** cleared outposts stay cleared and destroyed buildings stay destroyed between
  missions. Over campaign time, damage is repaired and the enemy reoccupies lost positions.
- **DECIDED Faction simulation:** between missions, factions run their own operations. They attack each
  other, take ground, and build or lose outposts, so the map changes even when the squad isn't deployed.
- **DECIDED War-driven contracts:** the faction war generates contracts. When a faction loses an outpost or
  plans an offensive, it posts matching jobs, such as retaking the outpost or raiding ahead of the push.
- **DECIDED Side lockout:** accepting work from one faction locks the squad out of its enemies' contracts
  for a while (proposed: until the current deployment ends plus a few campaign days, to tune).
- **DECIDED Briefings:** an Arma-style map briefing before deploying. It shows enemy positions known from
  intel, and the squad marks its plan and insertion point there and picks supports.
- **DECIDED Insertion:** the squad picks its insertion method per contract unless the client fixes it, and
  the environment limits the options. Heavy storms ground helicopters, AAVs are no use in mountains, and
  so on. In hot zones, supports are dynamic and live, and the risk is losing the asset itself (the
  helicopter or AAV and what it carries).
- **DECIDED Lost assets:** a destroyed support asset (such as a helicopter) is gone for the rest of that
  operation, and the player must pay to replace it after the op before it can be used again.
- **DECIDED Payment:** part of the pay comes as an advance up front to cover costs, and the rest is paid on
  completion. Proposed: an advance of about 30%, kept even if the contract fails, and part of the negotiation.
- **DECIDED Recruiting:** AI squadmates are hired from a rotating pool of contractors, each with a role,
  skills and wage demands. Veterans cost more.
- **DECIDED Squadmate progression:** AI squadmates improve by surviving missions. Their skills (aim, nerve,
  medical, etc.) rise along with their wage, so losing a veteran hurts.
- **DECIDED Injury carry-over:** squadmates with serious wounds (fractures, surgery, heavy blood loss) sit
  out for some campaign days to recover, and treatment costs money.
- **DECIDED Injured players:** if a player's character is seriously injured, it sits out to recover like an
  AI squadmate, and the player swaps to an available NPC squadmate character. If none is available, one
  is provided free of cost.
- **DECIDED Campaign time (hybrid):** each mission advances the clock, and travel between regions, recovery
  and repairs also take days. Proposed: wages and upkeep paid weekly, like MW5.
- **DECIDED Player characters:** each player has one main character and swaps to an NPC squadmate only
  while their main is recovering from serious injury.
- **DECIDED Debrief:** a full results screen after each mission with pay earned, bonuses and penalties,
  salvage to claim, casualties and injuries, rep changes, and intel turned in.
- **DECIDED Salvage:** everything the squad carries or extracts out is theirs. On top of that, the
  negotiated salvage share lets them claim items left in the field during the debrief, like MW5 salvage picks.
- **DECIDED Home base:** a mobile HQ that moves with the company between regions, like MW5's Leopard. The
  HQ is the LHD in coastal regions and the FOB inland, the same ones the supports launch from. It holds
  the armory, medbay and hiring board, which are upgraded over time.
- **DECIDED Contract generation:** most contracts are generated from templates by the faction war and
  intel, and a few handmade story contracts mark key campaign beats.
- **DECIDED Story:** a loose main storyline that surfaces every few weeks of campaign time and leads into
  the late-game player faction, plus short arcs for each major faction that unlock as rep with it grows.
  Main plot: someone is deliberately fueling the regional war, and a bigger, ruthless rival PMC is the
  public face of that conspiracy. The PMC keeps turning up on the other side of the player's jobs, intel
  slowly reveals who is behind it, and the story builds to taking them down as the player's faction rises.
- **DECIDED Rival PMC in play:** several rival contractor firms exist. The story PMC is often the rival team
  on regular jobs as well as the enemy in story contracts. Later in the story, it can also dispatch hit
  teams after the squad.
- **DECIDED Difficulty display:** each contract shows a 1 to 5 rating from enemy size and quality, plus
  known details like armor or AA. Better intel makes the estimate more accurate.
- **DECIDED Understated threats:** a client may lowball the threat or intel may be stale, so a briefing
  sometimes understates the opposition. When that happens the squad can renegotiate mid-contract or
  abort (proposed: without the rep hit, if the gap is big).
- **DECIDED First mission types to build:** raid (destroy a cache or AA site), HVT capture, hostage rescue
  and intel grab.
- **DECIDED LRRP missions:** some hot zones offer long-range reconnaissance patrols, where a small team
  moves deep into enemy ground undetected to uncover intel.
- **DECIDED Hot zone structure matters:** destroying parts of it weakens the enemy across the zone. Taking
  out a QRF base stops its reinforcements, a destroyed comms site slows their response, and killing
  officers makes patrols less coordinated. Baseline layout (confirmed): one enemy HQ, 3 to 6 outposts, a
  few road checkpoints, roaming patrols and 1 or 2 QRF bases with vehicles, with contracts on or near those sites.
- **DECIDED Hot zone alert level:** the zone starts calm. Noise, sightings and losses raise alertness, which
  means more patrols, closed checkpoints and QRFs on standby. Alertness eases if the squad goes quiet.
  There is no meter: players read alertness from intercepted radio chatter, patrol activity and closed
  checkpoints, in keeping with the minimal HUD.
- **DECIDED Radio interception:** looting an enemy radio lets the squad hear that zone's enemy chatter,
  revealing alert level and sometimes patrol or QRF movements, until the enemy notices and switches frequencies.
- **DECIDED Enemy supports:** better-equipped factions can call mortars, armed helicopters or drones on the
  squad at high alert. Destroying their comms or mortar sites removes that threat.
- **DECIDED Counter-drone:** drones can be shot down, or blocked by a jammer. The jammer is a heavy
  inventory item that blocks drones and radio nearby, including the squad's own radio.
- **DECIDED Squad drones:** small recon quadcopters the squad carries and flies to scout and mark enemies,
  with limited battery, and they can be shot down or jammed. FPV attack drones are also available as a buyable item.
- **DECIDED Hot zone start:** staged insertion. The squad inserts at the zone edge, or by helicopter or AAV
  from the LHD or FOB, and pushes in. Contracts appear on the map as the squad takes them from the board.
- **DECIDED In-zone contracts:** new contracts come in over the radio during a hot zone deployment, often
  reacting to what the squad has done (for example, after the squad hits a QRF base, a follow-up to hit the HQ).
- **DECIDED Hot zone pressure:** the longer the squad stays, the more the enemy commits (bigger QRFs, armor,
  hunter teams). Staying pays more but gets riskier.
- **DECIDED LRRP team:** a small detached team of 2 to 4 from the squad (players and/or AI) goes on the
  LRRP, while the rest wait at the LHD or FOB or work another contract.
- **DECIDED Enemy detection:** enemies spot by sight and sound, affected by distance, light, camo, stance,
  movement speed, foliage and weather. Suspicion builds before a full alert, giving the squad a moment
  to freeze or break contact.
- **DECIDED LRRP compromise:** being spotted doesn't fail the LRRP. The team can break contact and keep
  going, or call an emergency extraction. Intel not yet sent back is at risk if the team goes down.
- **DECIDED LRRP intel:** marking and reporting enemy positions by radio banks that intel right away. Photos
  and captured documents only count once they're carried out.
- **DECIDED LRRP length:** an LRRP can run for several in-game hours, with time acceleration while the team
  lies up in a hide. Fatigue matters. Food and water simulation is deferred (not a priority for now).
- **DECIDED Prep phase:** after accepting a contract and before the briefing, the squad kits up from the
  armory at the LHD or FOB, assigns squadmates and roles, and buys supplies.
- **DECIDED Contract end:** after the primary objective is done, the squad still has to reach an extraction
  point or call helicopter extraction. Loot only counts if it comes out with them.
- **DECIDED Optional objectives:** a couple are listed in the briefing, and others turn up in the field from
  intel or radio (for example, a weapons cache spotted on the way).
- **DECIDED Reputation tiers:** five tiers per faction, Hostile, Distrusted, Neutral, Trusted and Allied.
  Each step up unlocks better contracts, pay, gear, vehicles and supports. Hostile factions send hunters.
- **DECIDED Rep ripple:** gaining rep with a faction slightly raises it with that faction's allies and
  lowers it with its enemies (so the US, GB and Canada move together).
- **DECIDED Rep decay:** rep slowly drifts back toward Neutral if the squad stops working for a faction.
  Allied status needs only occasional jobs to keep.
- **DECIDED Allied troops:** some contracts are joint operations where a friendly unit fights alongside the
  squad as a separate AI group. The player can request their help but cannot command them directly.
