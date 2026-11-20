# Contractor: gate decision (2026-11-20)

**Verdict: NO-GO** for outside playtesters. Basis: all seven gate reports. Nobody played the game for these reports (code, docs and logs only). The one fresh run, R2931, failed.

## Must-fix, ranked

1. **Green the red suites and get one full-suite run on dev.** Owner: Cheeno.
   - `loadout` and `interaction` are red on dev HEAD 54ccc3d0 (R2931). Loadout has been red in 14 of 16 runs since 10-22. Interaction "shot through the hips" is a core wound-model check.
   - No full-suite green exists on the gate commit, and the two-process suites (supports, vehicles, net) have no recent evidence.
   - Cheeno owns the CI setup. First find out whether each failure is test-side or game-side. (QA Major 1, 2, 3.)
2. **Triage the 13 unmerged branches into dev, green ones only.** Owner: Cheeno.
   - Several fix known stalls and flakes (fix/city-stall, fix/ai-awareness-walls, fix/ci-flakes-nov). `ci/release-on-tag` is also needed for an exported build.
   - Cheeno owns them. (QA Major 4.)
3. **Clamp buy `count` to 1..50 in `_rq_buy` and `server_buy`.** Owner: Cheeno.
   - Suspected integer overflow, which lets a client bank a huge stack. Small fix, and the sell path already does it. Shared with Fallen. (Security Major.)
4. **Play one 20-minute contract on current dev, with a fresh screenshot set.** Owner: Captain.
   - There is one 0-error playtest (P2899) and no structured one. The 16 screenshots are from 9-10 Oct and show none of the current UI, vehicles or day/night.
   - Check the campaign camera 45-degree yaw and ADS offset (is it on B2897?). Capture soldier, zone day/dusk/rain, HUD, inventory and map. (Art Blocker 2; handoff bug.)
5. **Port Fallen's accessibility tab and solo pause; add Quit to the main menu.** Owner: Cheeno.
   - Fallen already has these (`accessibility.gd`, `solo_pause.gd`). Contractor has no colour-blind mode, no subtitle toggle and no text-size setting. A solo player is shot while the pause menu is open. (UX Major 1, 2; QA-explorer minors.)

## Deferred, with reasons

- **STYLE.md (art Blocker 1):** write it from the new screenshots after must-fix 4. Written now, it would describe a stale look.
- **Art Majors 3-6 (flat compound, default inventory look, dog tags, clean kit):** unverifiable until current captures exist. Re-judge then.
- **Polish Majors 1-4 (hit kick, noise shake, synth sounds, flesh impact):** playtest builds can ship with labelled placeholder audio. Hit kick and shake are small; do them after tester feedback on feel.
- **UX Major 3, 4 (pad rebinding, Ctrl/Alt rebind):** first playtesters get keyboard and mouse. Say so in the invite.
- **Security minors (join password, rate limits, marker caps):** the test group is invited, not public.

## Cut or freeze

- Freeze all new features. Vehicles, helicopters, supports and the business economy stay out of the playtest contract (independent reviewer). The code stays.
- Stop chasing the 30/30 FEATURES.md chart. It is marketing, not evidence.
- No new "waves" of parallel agents until suites are green.

## Care score: 6/10

I use the independent reviewer's. It was formed cold, and nothing in the other reports contradicts it. The thinking and test discipline are strong. Red suites, untuned "Proposed" numbers and no outside player evidence hold the score down.

## VISION.md and MILESTONES.md

Yes, both, before more features. There is no written definition of done, so the scope kept growing. Pillars should start from the wound model and AI squadmates that follow the same medical rules as players. Milestone 1 is one map and one contract, green and played.
