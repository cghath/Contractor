# Gate 2026-11-20: Contractor, independent reviewer (cold verdict)

Formed without reading the other gate reports. The game was not run: code, docs, commit history and test counts only.

**Verdict: a genuinely ambitious and mostly original squad-medical shooter, but it is a design document with a lot of working code attached, not yet a product a stranger can pick up.**

Evidence seen: ~275k lines GDScript in 498 files, 1,622 commits, 87 headless test suites, 1,103 audio files, README at v0.1.0. The last dev commits (Oct 27-30) are still "WIP dev reds": the squad-AI roles suite was red on dev (bounding pairs, R2870). The latest dev build (B2897, Nov 10) has no playtest record.

Compared with: Arma 3 + ACE3/KAT (squad care, wounds), Ready or Not / Ground Branch (tactical feel), Escape from Tarkov (body-part ballistics, armour), Squad (squad play), Door Kickers (readable tactical loop).

**Original:** the wound model (6 L blood, vessels, organs, per-bullet channels, no HP) plus NIJ/STANAG-named plates that crack and spall, inside a destructible voxel world, is a real thesis. AI treating casualties by the same rules as players is the strongest idea. Much of it is openly a port of ACE3/KAT mechanics. FEATURES.md says so and benchmarks against them. That's inspiration, not copying, but it isn't novelty either.

**Core loop:** contract, prepare at base, deploy, extract, get paid. It exists on paper and in code, but its moment-to-moment pull rests on the AI squadmates behaving, and the repo's own "In progress" list shows that is unsettled (spotting, morale, carry, doctrine).

**Generic or low-effort signals:**
- FEATURES.md's chart scores Contractor 30/30 on criteria "picked from our feature list". The doc admits it. It's marketing, not evidence.
- The voxel art generated in code is coherent, but the infil music is a public-domain 1921 recording marked temporary.
- The README needs a custom Voxel Tools editor build and a private repo. No exported installer path is documented beyond a launcher .bat that runs the editor.

**Scope:** breadth is out of control relative to depth. Vehicles, helicopters, supports, faction doctrine, a business economy, a tutorial and co-op netcode were all built at once; build_plan.md describes "waves" of 5 parallel agents. The feature list outruns anyone's ability to have tested it.

**Shippable?** No. Shortest honest path:
1. Freeze features and cut vehicles and supports from v1.
2. Take one 20-minute contract on one map to a clean, playtested, green-suite state.
3. Export a real build with templates, plus a plain-language controls and tutorial pass.
4. Run three outside playtests.

**Care: 6/10.** The thinking, research and test discipline are excellent. Finish is hurt by red suites, untuned "Proposed" numbers and no outside player evidence.
