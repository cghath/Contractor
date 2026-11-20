# Fallen: UX gate review, UX designer

Method: read code and docs only. I could not run the game. `screenshots/` holds 16 images, the same file names as the Contractor set (compound, dummies, inventory); I did not open them and found no Fallen survival screenshots. Nothing below was observed in play.

## Findings

### Blocker
None found in what I read. Docs list unfixed playtest bugs that affect first impressions (below); whether any is a blocker is the owner's call.

### Major
1. **Known first-impression bugs not started** (`docs/handoff_2026-11-10_playtest_bugs.md:61-72`): campaign view rotated ~45 degrees with ADS sight off-centre (campaign, not survival); ocean sound "louder and louder" inland; bleeding-out characters turn darker, unexplained. The doc is dated 11-10, so some may be stale; I didn't check later commits. Feedback and clarity checks.
2. **The 9 s control hint is the only first-hour teaching, and it is time-limited** (`scripts/survival/field_hints.gd:23`, `SHOW_S := 9.0`). Memory is fragile: a player mid-fight when "Melee" or "Injuries" fires loses it. Mitigated: hints are listed again in the journal's Field notes and Now list (`docs/survival_firsthour.md:61-62,85`). Fix: hold a hint until the player acts or pauses, or queue it.
3. **Hints resolve keys from the InputMap, but I found no gamepad handling** (grep for joy/pad in `field_hints.gd`: no matches). A pad player may see keyboard names; I couldn't confirm. Same pad gap as Contractor: pad layout is fixed in `autoload/controls.gd`, not rebindable.
4. **Text scale does not reach hand-drawn readouts**: marker labels and the medical diagram (`docs/survival_polish.md:82`). At 150% the body screen, where injuries are read, stays small. Accessibility check.

### Minor
5. **Colour-blind tab is off by default** (`survival_polish.md:65`). Players who need it must find it first. Consider asking at world creation.
6. **Palette is marked "Proposed"** (`survival_polish.md:68`), not tested with colour-blind players. Don't call it done.
7. **Solo pause exists** (`scripts/survival/solo_pause.gd`); I did not read it. Co-op can't pause (inherited text).
8. **Hint copy is clear and in voice** (`field_hints.gd:11-19`), e.g. "Hurt: {body_screen} opens the body screen, {medical_menu} the medical menu." Sample only.

### Strengths I verified in code
Accessibility tab exists with colour-blind-safe Okabe-Ito palette plus shapes so colour never carries a tell alone, text size 80-150%, subtitles toggle, tension audio toggle, hints toggle (`settings_menu.gd:216-235`; `accessibility.gd:1-31`). Tests cover the tab at 10 window sizes (`survival_polish.md:74`, claimed; I did not run them). Hints show once per profile with the player's own bindings. The journal's "Now" page gives the next goals with real keys.

## What's missing or not done for UX
- Gamepad: rebinding, and pad-aware hints and in-world prompts.
- Interactive tutorial for survival (the shared guide targets the Contractor compound; the survival menu section has only "new world" and "continue", `menu.gd:112-116`).
- A fresh round of screenshots of the survival HUD, body screen and journal: the folder holds old compound images only.
- Text scale on custom-drawn UI (item 4).
- Playtest evidence for build B2928 fixes (docs say "Not playtested yet", `handoff_2026-11-10_playtest_bugs.md:15`).
- Not verified: contrast ratios, HUD overlap, whether hints can fire while a menu is open.
