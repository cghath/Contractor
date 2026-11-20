# Gate 2026-11-20: Fallen, independent reviewer (cold verdict)

Formed without reading the other gate reports. The game was not run: code, docs, commit history and test counts only.

**Verdict: the more focused and more promising of the two, with a real thesis (a world that lives without you), but it is buried under its own documentation, and the owner's own first playtest said "not fun yet".**

Evidence seen: ~338k lines GDScript, 1,828 commits, 445 test files. docs/survival_firsthour.md records Captain's notes: "def needs more work before playtesting", didn't know the controls, nothing at the spawn, zombies too frequent. The latest handoff (docs/handoff_2026-11-10_playtest_bugs.md) lists a farm pickup spawned inside the farmhouse, no zombie sounds, and a knife that took ~750 stabs to kill a walker. The Nov 10 build is "Not playtested yet". The last commit (Nov 19) patched a collaborator's hordes and convoys.

Compared with: Project Zomboid (long-run survival, settlement), State of Decay 2 (settlement and people), DayZ/SCUM (scavenging, wear), RimWorld (bonds, colony sim), Kenshi (world sim).

**Original:** a world sim where households flee or hold against the dead, bonds form between pairs, convoys drive and get robbed, guns jam and wear, and the player starts on a farm with a 5-goal first day. The first-hour design (water, weapon, shelter, get the pickup running, a day-2 radio survivor) is how State of Decay and Zomboid onboard, done with thought. The mod kit and world cards are a good bet.

**Core loop:** farm, scavenge, fortify, survive the night, grow the settlement. It's a proven loop a player would repeat. Whether it holds is unproven: the only recorded player feedback is negative, and the fixes since are at the bug level, not the feel level.

**Generic or low-effort signals:**
- Dozens of docs per subsystem (seasons, children, clothing, bonds, mounts, gunsmith, wear), with numbers repeatedly labelled "Proposed", meaning untuned.
- "Where the build is" is a changelog of agent branches, not a state a player can use.
- Test flakes are being chased ("stealth-kill flake", R2751 FLAKY), so the suite is noisy.
- Zombie sound was missing entirely until Nov 10, a sign the breadth outran the basics.

**Scope:** also out of control. Children, gunsmithing, horses and farriers, tanning and bonds all exist before the zombie fight itself was fun (the knife melee was broken a week ago).

**Shippable?** No. Shortest honest path:
1. Cut to the farm, one town, nights 1-7 and one horde type.
2. Fix the melee and gun feel.
3. Get 5 strangers through the first hour with screen recording, and record what confuses them.
4. Only then touch the sim again.

**Care: 6.5/10.** A more coherent vision and heavy iteration on real player complaints, but the same untuned numbers and no outside tester yet. The first-hour and world-sim work shows more care for the player than Contractor does.
