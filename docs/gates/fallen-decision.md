# Fallen: gate decision (2026-11-20)

**Verdict: NO-GO** for outside playtesters. Basis: all seven gate reports plus the handoffs. Nobody played the game for these reports. The owner's last recorded playtest (B2903) was negative, and B2928 is unplayed.

Correction applied: HEAD daaaf2d1 was tested. R2930 ran on the working tree holding those changes before commit, and R2929 was a stopped run, not a failure. The qa-systematic "HEAD untested" Major is downgraded: one green run exists, but one green does not settle the survival suite.

## Must-fix, ranked

1. **Save the survivor on quit.** Owner: Cheeno.
   - Esc > Quit, main menu and window close never call `Survival.server_save`, and `server_stop` (`survival.gd:307`) has no caller. Within 5 minutes of the last autosave, items can vanish or duplicate, and the clock and needs roll back.
   - Also reset `Survival.running` on return to menu. Verified in `pause_menu.gd:165-170`. It is a clear code bug and needs no taste call. (QA-explorer Major x2.)
2. **Melee swing animation and windup tell.** Owner: Captain.
   - Confirmed: `melee.gd:7` claims "the arm goes back", but no code animates it. Neither the player's swing nor the zombie's 0.55 s lunge has a visible tell.
   - Captain chooses the timings by feel, since he has been playtesting melee. (Polish Blocker.)
3. **Rebuild from committed HEAD and play the first hour with screen recording.** Owner: Captain.
   - Check the knife, zombie sound, farm truck, engine loudness and 120 m start-safe zone. Capture the first Fallen screenshot set (survivor, zombies, farm, night, body screen, journal).
   - This also settles polish Major 6 (engine volume) and art Blocker 1's missing captures. (Playtest handoff.)
4. **Fix the ocean-louder-inland and bleeding-darker bugs, and stabilise survival tests.** Owner: Cheeno.
   - Work from Captain's description of triggers, not guesses.
   - Add tests for the dormant cold-open barn walker and the x0.75 tired swing.
   - Get `survival` and `firsthour` green repeatedly. `survival` was 6 red in a row on 11-10 and green once on HEAD. (QA Major 1, 3, 4.)
5. **Clamp buy `count` to 1..50 (shared RPC).** Owner: Cheeno.
   - Co-op griefing and overflow. The same small fix as Contractor.

## Deferred, with reasons

- **Seasons not drawn on terrain (art Blocker 2):** the playtest slice is nights 1-7 in one non-winter season. Do it after the slice is fun.
- **Campaign 45-degree camera and ADS offset:** a Contractor-campaign bug (Fallen's camera is fine). Tracked in Contractor must-fix 4.
- **STYLE.md:** write it from the must-fix 3 captures.
- **Art Majors (dog tags, zombie look variety):** unverifiable until captures exist.
- **Polish Majors 2-5 (hit sounds, shake, input latency, zombie audio):** these hang off the swing animation, so tune them after must-fix 2.
- **UX Majors 2-4 (9 s hints, pad hints, text scale on hand-drawn UI):** the journal repeats the hints. Captain's replay will show whether they bite.
- **Security minors:** the test group is invited. Document that mods are data-only.

## Cut or freeze

- Freeze children, gunsmithing, horses and farriers, tanning, bonds and new docs per subsystem.
- The playtest slice is the farm, one town, nights 1-7 and one horde type. Co-op is out of it, since no Fallen co-op run exists.
- The sim is not touched again until 5 strangers have played the first hour.

## Care score: 6.5/10

I use the independent reviewer's. It is higher than Contractor's because the first-hour design answers real player complaints and Fallen has accessibility and solo pause. It is capped by the melee gap, untuned "Proposed" numbers and no outside player yet.

## VISION.md and MILESTONES.md

Yes, both, and VISION first. The thesis ("a world that lives without you") is strong but exists only in scattered docs. Milestone 1 is "5 strangers finish the first hour".
