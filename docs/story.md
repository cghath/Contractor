# The story: a proposal

**Status:** drafted for the Captain's review (Captain, 2026-10-20: "Draft, then I review"). He
then picked four of the big calls the same day: **the mastermind is the consortium (A)**, **four
acts**, **act 1 is the four beats with the FOB after**, and **intel moves the arc both ways** (each
story contract needs its own clue; the evidence count gates the acts). Act 1 is built on that.
Everything else is still **Proposed**, and the calls left open are listed in section 8.

## 1. What's decided (Captain)

From mission_brainstorm.md ("Story", "Rival PMC in play"), the design doc ("Missions") and
ChrisPlan_handoff.md ("Quest, story" items):

- A **loose main storyline that surfaces every few weeks of campaign time** and leads into the
  late-game player faction, plus **short arcs for each major faction** that unlock as reputation
  with it grows.
- **Main plot:** someone is deliberately fuelling the regional war, and a bigger, ruthless rival PMC
  is the public face of that conspiracy. The PMC keeps turning up on the other side of the player's
  jobs; **intel slowly reveals who is behind it**; the story builds to **taking them down as the
  player's faction rises**.
- The story PMC is the **Vantage Group** (faction set, wave 6b call 4). It's often the rival team on
  regular jobs (RivalTeam already races the squad and its leaders carry a `vantage_ledger`), the
  enemy in story contracts, and later it **sends hit teams** after the squad.
- **The early game is mostly fighting terrorist factions** (Black Ridge).
- Contracts are mostly generated; **a few handmade story contracts mark the key beats**.
- **Intel is a physical item that opens leads.** Story items are "rival PMC evidence (ledgers,
  contracts, a drive), crash-site flight recorder", set by the contract.
- Heat brings bounty hunters; at high heat, **Nemesis-style named hunter squads** (built in wave 6d).
- Home is the LHD until the company takes a zone for its FOB (docs/lhd_home.md, built).

## 2. Who's behind it: the mastermind (Captain: A, the consortium)

| | Who | The twist | What it does to the late game |
| --- | --- | --- | --- |
| **A** | A **reconstruction and shipping consortium** (working name: Halden). It wins the rebuilding contracts, runs the ports and sells to every side. | Nobody in uniform. The war is a business plan. | The player faction's rise is economic as much as military: take their ports, contracts and backers away. |
| **B** | An **allied government's intelligence service**, running a deniable proxy war through Vantage to keep a rival power bogged down. | The company's own allies (the US, UK or Canada employers) are paying for it. Reputation with them turns double-edged. | The player faction breaks from the allies. A real choice: expose them and lose allied gear and support, or stay quiet and keep it. |
| **C** | **Meridian Logistics**, the company's first employer. It hires the player to clean up the fires its own partner, Vantage, keeps lighting. | The client who's been paying you since day 1. | Meridian goes from employer to enemy mid-campaign. The player faction takes over its contracts and its region. |

**Captain, 2026-10-20: A.** The consortium's name (Halden) is still a working name (Proposed).
**Proposed:** B's allied officials appear as its customers in act 3.

## 3. The main arc in acts (Captain: four acts)

The acts' names, reveals and endings are Proposed.

| Act | Working name | Home | What the intel shows | Ends with |
| --- | --- | --- | --- | --- |
| 1 | The coast | the LHD | Black Ridge's new weapons aren't smuggled. They're delivered, and Vantage is the one delivering them. | Proof that Vantage arms Black Ridge. |
| 2 | Ashore | the FOB | Vantage works for someone. The money trail leads to the mastermind's front. Vantage starts sending hit teams. | The front's name. |
| 3 | The money | the FOB | Who the mastermind is, and who protects them (section 2). | A turning point: the allies won't act, or can't. |
| 4 | The company's own | the FOB | The player faction goes after the mastermind directly (the campaign-operation tier). | Taking them down. |

**Pacing (Proposed, from "surfaces every few weeks"):** a story contract can't come up within
STORY_GAP_DAYS (Proposed: 10) of the last one. Act 1 runs 3-4 story contracts over the first
4-6 campaign weeks, while generated work fills the time between.

**Pacing is not built yet:** the gap between story contracts waits for the Captain's call.

**Act 1 (Captain: these four beats, built; the FOB comes after).** The client is Meridian. Each beat
is an existing contract type (data/contracts.json `"story"`). Titles, briefs, clue text and the
liaison's lines are Proposed:

| # | Contract | Type | Needs | Its clue (evidence) |
| --- | --- | --- | --- | --- |
| 1 | Paper trail | intel grab, against Black Ridge | the campaign's start | Crates with a contractor's shipping marks (1) |
| 2 | The quartermaster | two-zone manhunt | 1 done, its clue | He paid a Vantage Group account (1) |
| 3 | The crates | two-zone supply line, plus the waybills | 2 done, its clue | Vantage escorts the convoys (1) |
| 4 | Vantage point | raid against Vantage, for its ledger | 3 done, its clue | Vantage pays Black Ridge, and is paid through Halden Maritime (2) |

## 4. Named characters (Proposed, all names placeholders)

- **The client's liaison**: the voice on the radio who calls story contracts in, in the style of
  the LHD's liaison lines (zone_control.gd). Alternatives: one liaison for the whole story, or one
  per employer.
- **A Vantage field commander**: the face of Vantage, who leads the hit teams from act 2. Tie them
  to the Nemesis system: a named hunter squad that remembers the company. Killed, they're replaced
  by a worse one. Alternative: they survive to act 4 however often their teams are beaten.
- **Someone inside the conspiracy who wants out**: a source who feeds the company leads in act 3.
  Alternatives: a Vantage contractor, a consortium accountant, or an allied officer (fits B).

## 5. How intel moves the arc (Captain: both, C)

- **A. Evidence count (built as plumbing).** Clues found add evidence. A story contract opens once
  the one before it is done and the count reaches its number. Ordinary intel adds to it too
  (Proposed: 4 pieces turned in = 1 evidence; each Vantage ledger = 1, up to 3), so normal work
  moves the story along. Selling intel gives none. Simple, and hard to soft-lock.
- **B. Clue board.** Named clues, each from a specific item (the ledger, the drive, the flight
  recorder). A story contract needs particular clues, not a count. More authored; a lost clue needs
  a way back in (re-offered intel).
- **C. Both (Captain, 2026-10-20; built).** Each story contract needs the clue of the one before
  it. The evidence count gates the acts: Proposed, act 2 at 6, act 3 at 10, act 4 at 14. Act 1's
  clues make 5, so a little ordinary intel (or one Vantage ledger) is needed on top to open act 2.
  A done contract always brings its clue (its required objective is the intel), so no clue can be
  lost.

Either way the Leads section on the contract board shows the act, the evidence, what the next
story contract waits for, and every clue's line so far (text only).

## 6. Faction arcs, hit teams, the LHD (Proposed)

- **Faction arcs**, each opening at Trusted (30), 2-3 story contracts long. Candidates:
  - Meridian: a manager signing Vantage's escort deals (this clashes with mastermind C).
  - The Coastal Salvage Union: their boats see every ship, so they trade shipping intel.
  - The US forces: joint operations, and they share what they know of Vantage (this becomes
    double-edged under B).
- **Hit teams:** from act 2, at high Vantage heat, a named Vantage hunter squad comes on any
  deployment. From act 3, they can raid the FOB (LZ-5's assaults). These use what's built
  (EnemyResponse hunters, Economy's nemesis records, RivalTeam).
- **The LHD-to-FOB beat** stays as built. **Captain:** act 1 plays from the LHD, and act 2 opens
  once act 1 is done and the FOB is built, in either order (and the evidence count is reached).

## 7. What's built

`scripts/campaign/story.gd` (class `Story`), campaign section `"story"`, data in
data/contracts.json `"story"`. Tests: `tests/story_test.gd`.

- **State:** act, evidence, scraps, ledgers, clues, done, offered, back_day, acts_done. Saved with
  the campaign; clients get it in the contracts' view.
- **Story contracts from data:** an existing type with its own name, brief and objectives
  (ContractGen's `"def"`; an objective may place its own piece, such as the ledger). One goes on the
  board once the contracts in its "after" are done and its "clues" are found. It never expires
  there, and comes back the day after a failure. Done, it brings its clue, and the liaison says so.
- **Acts:** an act closes with its last contract. The next opens once it's written, its "evidence"
  count is reached and the FOB is built ("needs_fob").
- **Intel advancing the count:** ordinary intel and Vantage ledgers turned in at the debrief add
  evidence (section 5's numbers).
- **Leads:** a text section on the contract board: the act, the evidence, what the next story
  contract or act waits for, and every clue so far.
- **Act 1's four contracts** (section 3). Acts 2-4 and the faction arcs are data stubs.

## 8. Calls still open for the Captain

1. The names and text: Halden, the clue lines, the liaison's lines, the act names.
2. The pacing gap between story contracts (Proposed: 10 days; not built).
3. The characters: one liaison or one per employer, and the Vantage commander as a Nemesis hunter (section 4).
4. The evidence numbers: 4 ordinary intel = 1, ledgers 1 each up to 3, acts at 6 / 10 / 14 (section 5).
5. The faction arcs, and whether they open at Trusted (section 6).
6. The hit teams' timing: from act 2 on deployments, from act 3 at the FOB (section 6).
