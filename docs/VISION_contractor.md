# Contractor: Vision

Status: draft for Captain, 2026-11-20. Sources: contractor_handoff.md (authority), contractor_design_doc.md, FEATURES.md, README.md, the 2026-11-20 gate reports.

## Pitch

Command a squad of contractors through a persistent campaign where nobody has hit points: every wound is blood, vessels and organs, and your AI squadmates treat casualties by the same rules you do.

## Who it's for

A solo player who likes Arma-style tactical shooters and wants the squad to be real. They are patient, read their own kit, and would rather save a bleeding buddy than win a score screen. They play alone with AI squadmates. Two to four players in co-op is supported (host-authoritative, up to 4 humans of 8 slots) but the game is tuned for one.

## Pillars

1. **The body is the health bar.** 6 L of blood, simulated vessels, organs, breathing, per-round wound channels, no HP. *A feature serves this pillar if it changes what a wound does or what treating it costs, and shows it through the body or the kit, not a number.*
2. **The squad plays by our rules.** AI squadmates and enemies use battle buddies, carry, drag and treat, under the same medical and ballistic rules as players. *A feature serves this pillar if an AI can do it the way a player does, and fail the way a player fails.*
3. **Everything has weight.** Physical inventory in litres, momentum in movement, armour that cracks and spalls, impact that bruises and breaks. *A feature serves this pillar if carrying, moving or being hit costs something you can feel.*
4. **The campaign remembers.** Cash, supports, shifting territory, permadeath for AI, gear left where a player fell. *A feature serves this pillar if it makes the next contract depend on the last one.*

## Core loop

- **Minute to minute:** move as a fire team, spot, engage, then treat the wounded: tourniquet, seal, IV, with buddies covering.
- **Session:** take a contract or hot zone, deploy, finish or lapse, extract (evacuated loot banks at once).
- **Campaign:** cash buys gear, repairs, medical stock and support calls (Blackhawk resupply and transport, AAVs, extraction); territory and reputation shift between missions; AI casualties are lost or recovered.

## What makes it ours

Honest comparables: Arma 3 with ACE3 and KAT (wounds, care), Ready or Not and Ground Branch (tactical feel), Escape from Tarkov (body-part ballistics, armour), Squad.

The medical and ballistics model openly borrows ACE3 and KAT ideas and their ballistics values (checked in game); FEATURES.md says so. This is inspiration, not novelty. Where we go further, per our own FEATURES.md: simulated vessels and organs with bleeding scaled by how close a round passed and its cavitation, breathing and alveolar efficiency, surgery kits that clamp torso arteries, NIJ 0101.07 plate ratings with ceramic crack zones, wounds modelled inside a destructible voxel body, and AI that treats casualties by those same rules. We are not ahead everywhere: FEATURES.md concedes our body doesn't compensate for blood loss and bleeds don't clot. Its 30/30 chart is self-selected criteria; it is not proof.

## Tone and feel

Gritty and realistic. Information is diegetic: no health bar, no ammo counter. Real guns, real standards, real terminology. Weight and consequence over spectacle. One realistic difficulty, with optional assists.

## What v1 means

v1 is a free, invite-only closed playtest. No store yet. **Everything built stays in v1**: vehicles, helicopters, supports, economy, factions and co-op. The goal is coherence, not trimming. The bar for each system: finished, tuned (no "Proposed" number left in the core loop), tested (green suite, run on the shipped commit) and playtested by someone other than its builder. Gate status 2026-11-20 is NO-GO: red suites, untuned numbers, no structured playtest.

## Non-goals

- No hit points, health bars or ammo counters.
- No pay-to-win, no store, no public release in v1.
- No new features that skip the bar above.
- No arcade difficulty ladder; assists only.
- No copying ACE3, KAT, LAMBS or VCOM code; we study and rebuild.

## Captain's decisions (2026-11-20)

1. **No cuts:** everything built stays in v1.
2. **Solo first,** co-op a bonus.
3. **v1 is a free closed playtest** (invite-only, no store).
4. **The first playtest is one contract, start to finish, in the full game.** The infantry, medical and squad loop reaches the bar first; vehicles, supports and the economy get their finishing passes after it, still before v1.
5. **Body compensation (heart rate rising with blood loss, clotting) lands before the first playtest:** pillar 1 shouldn't go out with its named gap.
6. **Playtesters are Cheeno and friends:** people who didn't build the system they're testing. Informal, but every session leaves notes (and the RPT/session log) that go through `/feedback`.
