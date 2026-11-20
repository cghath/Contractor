# Contractor: QA explorer gate report (read-only, code-traced)

Checkout: B:\Contractor-build-dev. Method: code reading only, no play. I hit the turn limit; coverage is partial (see "Not reached").

## Charter 1: Explore save / quit / Continue at odd moments (pause menu, save code) to find lost or stale progress
- No bug found in the hardened save path: temp file, backup, and set-aside of unreadable files (autoload/campaign.gd:98 and :112; autoload/game_state.gd:86). CONFIRMED sound as read.
- Window close while hosting a campaign is covered by two handlers: scripts/main.gd:49 (zone) and scripts/campaign/base_hub.gd:3695 (campaign). CONFIRMED fine.
- Minor, CONFIRMED: quick_save (Home) is handled twice (scripts/main.gd:44 saves the zone; base_hub.gd:3685 saves the campaign), so the zone is written twice per press. Harmless.
- Design observation (non-bug): the pause menu does not pause the game (scripts/ui/pause_menu.gd header). A solo player pressing Esc mid-fight is still shot. Fallen added SoloPause; Contractor solo has none.

## Charter 2: Explore the main menu and first-run flow as a confused new player
- Minor, CONFIRMED: "Reset plain-session compound save" deletes the save, .tmp and .bak in one click with no confirm (scripts/ui/menu.gd:287, autoload/game_state.gd:497). The campaign archive button has a two-click confirm (menu.gd:297). A mis-click loses the plain compound.
- Minor, CONFIRMED: the main menu has no Quit button (no "quit" anywhere in scripts/ui/menu.gd).
- Minor, CONFIRMED (wording): "Campaign: host at the base (FOB)" (menu.gd:276) both starts and resumes; nothing tells a first-hour player whether a save exists.
- Minor, SUSPECTED: five debug "Test zones" buttons sit beside the real play buttons.

## Charter 3: Explore death/respawn and settings for stuck states
- No bug found: respawn serial guards stale timers (scripts/actors/soldier.gd:2677-2740), vehicles handle dead occupants (scripts/vehicles/vehicle.gd:1815). Read, not played.
- Minor, SUSPECTED: scripts/ui/game_settings.gd _load does int(cfg.get_value("keys", action)) on a hand-editable settings.cfg; an array or dictionary value would error. Not traced to a crash.
- Design observation: E/Q/X/C are shared between lean/lase/designate/hatch/crouch/mount (autoload/controls.gd); rebinding one needs a note about its seated twin.

## First-hour player: missing or unfinished
- No Quit on the main menu; no solo pause; no Continue/New distinction on the campaign button.
- Open items in docs/audits/followups.md a first hour can hit (listed from the doc, not re-verified): F-122 (first late join to the vehicle range drops after ~50 s), F-193 (player down after helicopter insertion, CI only), F-179 (hand flare not fireable by players), F-160 (dog tags have no worn model), F-130 (AI grenadier never fires M320).
- Owner's handoff (Fallen checkout) says the campaign camera is ~45 degrees off the body and ADS sight is offset, not started; not verified here.

## Not reached (no claim made)
Multiplayer join mid-event, vehicles and ragdolls in odd terrain, inventory edge cases, loadout editor back-outs. Contractor has no sleep (grep found no time_scale or tree pause).
