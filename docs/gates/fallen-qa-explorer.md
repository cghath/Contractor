# Fallen: QA explorer gate report (read-only, code-traced)

Checkout: B:\Contractor-build-fallen (fallen/nov10-playtest). Method: code reading only, no play. I hit the turn limit; coverage is partial.

## Charter 1: Explore quit / Return to main menu / Continue (pause menu, Survival save code) to find lost or duplicated progress
- MAJOR, CONFIRMED in code (not played): quitting a survival world never runs Survival.server_save. PauseMenu._save writes only GameState.save_zone(), plus BaseHub.server_save() when BaseHub.campaign_running (scripts/ui/pause_menu.gd:165-170). Fallen worlds start through Survival.server_new_world / server_continue (scripts/ui/menu.gd:188, :203); I found no code that sets campaign_running for them. Window close (scripts/main.gd:49) saves the zone only. No caller of Survival.server_stop (autoload/survival.gd:307) exists in scripts/ or autoload/. The only caller of Survival.server_save is the 5-minute timer (survival.gd:437, SAVE_MIN 5).
  Repro: Continue a world, pick up or drop items, within 5 minutes press Esc > Quit game (or the window X). The zone save has the new loot/drop state; the survivor's kit, needs, position, day/hour and journal (_store_survivor, survival.gd:561) are up to 5 minutes old. On Continue, items can vanish (taken from the world, not in the kit) or duplicate (dropped in the world, still in the kit), and the clock and needs roll back.
  Not verified: whether some other hook saves the campaign on quit (I grepped scripts/ and autoload/ only).
- MAJOR, SUSPECTED: Survival.running is never reset on Return to main menu (only server_stop sets it false, survival.gd:309, and nothing calls it). Code gated on it (scripts/survival/clothing.gd:51, wear.gd:28) would stay active in a later non-survival session. No visible symptom traced.
- Minor, CONFIRMED: quick_save (Home) in survival saves the zone only (scripts/main.gd:44): same split.

## Charter 2: Explore sleep and waiting (SurvivalSleep, server_tick_survivors)
- Minor, CONFIRMED: body stepping is skipped for a non-up survivor (survival.gd:1004), but the "down" wake lives in SurvivalSleep.after_step (survival_sleep.gd:72), reached only through server_drain. A survivor who goes down while asleep or waiting keeps asleep / wait_left_h set; revived in place he is still "asleep" with body time at x12 until he moves 1.5 m or the hours run out.
- Minor, SUSPECTED: Needs.respawn (scripts/survival/needs.gd:125) resets "asleep" via fresh() but fresh() has no wait_* keys, so a stale wait could carry into the new survivor. I did not confirm a death can happen without a prior wake.
- Minor, CONFIRMED (wake list traced): nothing wakes a sleeper on damage. Reasons are chase (survival.gd:1006-1009), moved, rested, down. Fire, predators or a non-zombie attacker that causes no ZombieAI CHASE would not wake him. Real-play effect SUSPECTED.
- Minor, SUSPECTED: wait_interrupt uses distance (30 m), not line of sight, so a walker behind a wall cancels a wait.
- Design observation: the x12 world clock needs every up survivor asleep or waiting (clock_mult), and a downed co-op partner is excluded from "every", so a bleeding teammate does not hold the group back.

## Charter 3: Owner's playtest notes (docs/handoff_2026-11-10_playtest_bugs.md)
Read, not re-verified in code.
- Not started per the handoff: campaign camera ~45 degrees off the body and ADS sight offset (campaign only); ocean sound growing louder at the inland farm; bleeding-out characters turning darker.
- Handoff admits no test covers the dormant cold-open barn walker or the x0.75 tired-swing damage, and build B2928 was not playtested.
- SoloPause (scripts/survival/solo_pause.gd) reads correctly: pauses only with zero peers, unpauses on join. Edge not checked: a zone transition or death while the tree is paused.

## First-hour player: missing or unfinished
- Quitting mid-session can lose or duplicate gear (Charter 1).
- The three not-started bugs above; the 26fbc269 fixes (zombie sounds, knife, farm safety) are covered by suites only, not owner play.

## Not reached (no claim made)
Co-op join mid-event (CoopFallen), vehicles and ragdolls in odd terrain, inventory edge cases, build-mode back-outs, left-handed setting in survival, convoy/horde interrupts, New World screen input validation, WorldListScreen with a corrupt world.
