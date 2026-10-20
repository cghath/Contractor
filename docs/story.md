# The story

The campaign's story as decided, and how it plays. **Captain** marks his calls (from the design doc,
"Missions"); **Proposed** marks mine, for him to confirm or change. Code: `scripts/campaign/story.gd`
(class `Story`, campaign section `"story"`), data: `data/contracts.json` `"story"`. Tests:
`tests/story_test.gd`.

## 1. The shape

- **Captain:** a loose main storyline plus per-faction arcs that unlock with reputation. Contracts are
  mostly generated from templates; a few handmade story contracts carry the key beats.
- **Captain:** the main plot: a rival PMC, the **Vantage Group**, is the face of a conspiracy fuelling
  the regional war. The player's intel slowly uncovers who is behind it, leading toward the late-game
  player faction. The early game is mostly fighting terrorist factions (Black Ridge).
- **Captain:** intel is a physical item that opens leads. The rival PMC can later send hit teams; heat
  brings bounty hunters, and Nemesis-style named hunter squads at high heat.

## 2. The main arc, in acts

| Act | Name | Where home is | What the player learns | Status |
| --- | --- | --- | --- | --- |
| 1 | The coast | the LHD | Black Ridge isn't smuggling its weapons; a contractor ships them, and that contractor is Vantage. | **Built** |
| 2 | Ashore | the FOB | Vantage isn't freelancing: it arms both Black Ridge and the Eastern Concord's officers, and its pay comes through a shipping front (Halden Maritime). | Data stub |
| 3 | The money | the FOB | Who owns Halden: a consortium that profits from the war going on (contracts, reconstruction, the ports). Vantage hit teams come after the company. | Data stub |
| 4 | The company's own | the FOB | The allies won't move against the backers. The company becomes its own faction (the late-game player faction, campaign operations). | Data stub |

All of act 1 and the names in acts 2-4 (Halden Maritime, the consortium) are **Proposed**.

**Proposed, how an act moves on:** each act has its story contracts in order. A story contract goes on
the board once the ones before it are done and the evidence count reaches its number; it stays there
until taken (no expiry), and a failed, aborted or lapsed one comes back the next day. An act closes
when its last contract is done. Act 2 also waits for the FOB (section 7).

## 3. Act 1, "The coast" (built)

The client is **Meridian Logistics** (the company's first employer); the enemy is **Black Ridge**
until the finale, which is against **Vantage**. All four are existing contract types with their own
title, brief and objectives (data/contracts.json `"story"."contracts"`). **Proposed**, all of it.

| # | Contract | Type | Unlocks when | The intel, and what it says (the clue) |
| --- | --- | --- | --- | --- |
| 1 | **Paper trail** | intel grab | the campaign starts | Black Ridge's laptop: their rifles came in sealed crates with a contractor's shipping marks, not smuggled. |
| 2 | **The quartermaster** | manhunt (two zones) | 1 done, evidence 1 | Black Ridge's quartermaster, taken alive next door: he names who he paid, a Vantage Group account. |
| 3 | **The crates** | supply line (two zones) | 2 done, evidence 2 | The waybills at the cache: Vantage escorts the convoys that bring the crates in. |
| 4 | **Vantage point** | raid | 3 done, evidence 3 | A Vantage team's field ledger (`vantage_ledger`): Vantage pays Black Ridge's commanders, and the money comes through Halden Maritime. Act 1 closes. |

The liaison calls each one in on the radio when it goes on the board, and again when it's done
(`Story.LINE_*`, in the style of zone_control.gd's).

## 4. Intel and the evidence count (the clue board)

- **Proposed:** the story keeps a list of **clues**, each a line of what a piece of intel said, and an
  **evidence** count. The contract board shows them under **Leads** (text only): the act, the evidence
  count, what the next story contract waits for, and every clue so far.
- A story contract's clue comes from its intel: its required objective is the intel itself (the laptop,
  the quartermaster, the waybills, the ledger), so a contract done means the intel came out with it.
  Each clue is worth 1 evidence, the ledger 2.
- Other intel counts too, so ordinary work moves the story along: every 4 pieces of ordinary intel
  turned in at a debrief is 1 evidence ("scraps"), and each Vantage ledger turned in (the rival teams'
  leaders carry them) is 1 more, up to 3. Selling intel to another faction gives no evidence.
- The evidence count only opens a story contract once the one before it is done, so it can't skip the
  story ahead. It does mean a player who sells or loses a clue can still go on.

## 5. Faction arcs (data stubs)

**Captain:** per-faction arcs unlock with reputation. **Proposed:** three, each opening at the
Trusted tier (30) with that faction, two or three story contracts long:

| Arc | Faction | Opens at | The thread |
| --- | --- | --- | --- |
| Company man | Meridian Logistics | Trusted | A Meridian manager has been signing Vantage's escort contracts. Expose him or keep it quiet for a price. |
| Salvage rights | Coastal Salvage Union | Trusted | The Union's boats see every ship that comes in. Protect a salvage job; they trade what they know of Halden's shipping. |
| Liaison | US Forces | Trusted | Joint operations with the allies: a downed crew, a defend-and-hold. They share what they have on Vantage, and later won't act on it. |

## 6. Hit teams and named hunters

What's already built carries on: rival Vantage teams race the squad for some contracts (RivalTeam),
heat brings hunter teams, and named hunter squads come back at high heat (EnemyResponse, Economy's
nemesis records, wave 6d). **Proposed** for the story:

- From act 2, Vantage itself sends **hit teams**: at high Vantage heat, one of its named hunter squads
  comes after the company on a deployment, whatever the contract, and its leader carries a ledger.
- From act 3, a hit team can come for a squadmate at the FOB (a defend-the-base beat, LZ-5's assaults).
- Not built yet: acts 2-4 are data stubs, so nothing here changes how the hunters work today.

## 7. The LHD and the FOB

The LHD session's beat (docs/lhd_home.md, zone_control.gd) stays as it is: a zone flips once its HQ
and QRF bases are down, the client's liaison says the LHD's charter is running out, and a
seize-and-hold contract there makes it the FOB. **Proposed:** act 1 plays from the LHD, and **act 2
opens once act 1 is done and the FOB is built**, in either order. Done with act 1 while still on the
LHD, the liaison says the next leads are inland and the company will need ground of its own.

## 8. Calls for the Captain

1. Act 1's four contracts, their order and their clues (section 3).
2. The evidence rules: clue 1 each (the ledger 2), 4 ordinary intel = 1, Vantage ledgers 1 each up to
   3, selling gives none (section 4).
3. Story contracts never expire, and come back the day after a failure.
4. The names: Halden Maritime (Vantage's paymaster) and an unnamed consortium behind it; acts 2-4.
5. The three faction arcs, opening at Trusted (section 5).
6. Act 2 waits for both act 1 and the FOB (section 7).
7. Leads on the contract board, as text (section 4).
