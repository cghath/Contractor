# Handoff: everything Claude has in flight, for cghath to pick up

Kept current by Claude at every landing. It's the single place that says where each piece of work
stands, so nothing gets lost if Claude's usage runs out (the handoff point is weekly usage at 99%;
the reset is **Sunday Oct 25, 10:00 CDT**). If you're picking this up, start at "State", then
"Open work". The decisions are already made: docs/cg_brief.md "Decisions already made",
docs/combined_arms.md section 10, and Captain's asks below. Make the call and keep going.

Last updated: 2026-10-22 13:05 CDT (claude/ai-driving 494fb4f3 plus this doc).

## State

claude/ai-driving is the integration branch. dev caught up on 2026-10-22 (3c2ba039, via the CI
cleanup); it moves again once claude/ai-driving's CI is no worse.

| Work | Branch | In claude/ai-driving? | Status / next step |
|---|---|---|---|
| Design doc (combined arms) | claude/combined-arms-doc | yes | Done: docs/combined_arms.md |
| AI follow-ups F-140/162/176, G-14/24/26 | claude/ai-followups | yes | Done |
| CI cleanup, dev catch-up, AAV fix | claude/ci-cleanup | yes | Done. Known reds left: exo, mech, nvg, loadout, vehicles (480 s timeout on the base), gameplay, armour (fail on the base too) |
| Performance pass | claude/perf-pass | yes (df3133f0) | Done. Town 50.7→21.4 ms, heli stutters gone; perfcases suite; "World detail at distance" setting; F-206 lists what's left |
| D7: US forces in the living war | claude/ca-d7-us-war | yes | Done |
| A1: the armour model | claude/ca-a1-armour-model | yes | Done. Next is your cg_brief 2.0 (standards pass), then A2 |
| C lane: high command C1-C6 | claude/ca-c-high-command | yes (df3133f0) | Done: two HC squads from the start, Phase 2 orders, map-order HUD with gun cone of fire, 3D HC camera, contextual menus |
| B lane: AI commander + tactics | claude/ca-b1-side-picture | yes (2026-10-22 ~13:30) | Done: B2 commander, B3 armour with infantry, B5 deconfliction, B4 requests carried out; docs/ai_tactics.md and the drills by echelon for every side; terror groups that grow. Deferred (doc calls 12, 13, 19): wider spacing in cover (waits for a playtest), smoke before a breach beyond bunkers, dug-in positions and IEDs scaling with group size. Radio voice clips need Piper rendering (subtitles meanwhile) |
| D1/D2: 8 km operation zones | claude/ca-d1-operation-zones | no | **Yours** (cg_brief 3.1). D1 done; D2 untested WIP |
| Your world/water, missions-2, voxel smoke, demolitions | (yours) | yes (00f3e731) | Merged 2026-10-22 for v0.5.3 |
| Your world/perf stack (roads, terrain, cities, village houses, props, perf) | world/perf, via claude/merge-world-perf | yes (9729d106) | Merged with our perf pass (both kept in zone_scatter.gd). Your content roughly doubles town and heli frame cost, so the perfcases budgets were re-based; worth a perf look. **In v0.5.3 (B2493)** |
| Tactics reels → AI spec | docs/tactics/, docs/ai_tactics.md | yes | Done from 10 reels (13 gone, skipped on Captain's call); see the B lane row for what was deferred |
| 3D loadout editor + 3D armory | claude/loadout-3d | yes | Done: 3D soldier with clickable slots, buy-in-place and "Buy missing", saved kits applied to anyone incl. Hawk 2/Viper 3, armory room by shelf. Not yet seen in game: check marker placement on the female build, gun rail markers, shelf spacing (docs/loadout_3d.md) |
| Mission UI pass | claude/mission-ui | yes | Done (9aa87f16): contract board, briefing, objectives tracker, debrief; contracts, missions, ui, smoke pass (R2510, R2511). Not yet seen in game |
| Town perf follow-up | claude/perf-towns | yes | Done (a38fab7e): city 136→103 ms, fight 62→35, woods 25→14, drive 16→8.5, heli 15→10.6 ms with hitches 27→3/min; perfcases budgets tightened. Cities are still the heaviest case |
| Voice + economy tuning | claude/voice-economy | no | Built and pushed: context-aware barks with priorities and one voice per group, voice orders (callsigns, HC squads, go codes, confirmations), docs/voice.md; economy pass (standing squads' own field rate, insertion priced, shock costs down, pay up a third) with before/after curves in docs/economy.md. Local: smoke, voice, contracts, roles pass (R2526-R2529; roles needed a fix for perf-towns' kept slots holding freed men, SquadAI._apart). Next: CI, merge into claude/ai-driving; render the 81 lines in tools/voices/lines_to_render.txt with Piper later |
| Income systems (v0.5.4) | claude/income | no | 3/4 built: HC squad side jobs (SideJobs), captures + bounties + intel buyers (Bounties), FOB businesses (FobBusiness); Side work page, board line, income suite. Next: 4 black market (script drafted, not wired), 4 black market, then the economy sim re-run and tuning (docs/income.md, CHANGELOG "Income" note) |

## Open work, in order, and who has it

**Yours** (docs/cg_brief.md items 1-16): the world expansion first, then items 2-4 (armour,
operations, vehicle art), then the rest.

**Claude's, until the handoff; then yours.** The design for all of it is docs/combined_arms.md.
1. **CI cleanup** (claude/ci-cleanup): finish the reds. Known reds:
   - vehicles times out at 480 s on the base;
   - nvg exits 1 after passing;
   - casualty "stuck on the way" (F-08);
   - squad stair clearing;
   - loadout teardown;
   - missions "every zone is a generated layout" (on the base since a recent merge);
   - gameplay (fails on the base too).
   Then merge into claude/ai-driving and fast-forward dev to a green (or flakes-documented)
   commit.
2. **Performance pass** (claude/perf-pass): land the fixes in stages, with frame-time and hitch
   budgets in the perf suites. D2 (8 km) is separate and yours.
3. **C lane** (claude/ca-c-high-command), C1 → C6:
   - two high command squads from the start;
   - Phase 2 orders;
   - the map-order HUD;
   - gun placement with a visible cone of fire;
   - the 3D high command camera (known contacts only);
   - contextual menus.
4. **B lane** (claude/ca-b1-side-picture): B2 (the commander, after C2), B3 (armour with
   infantry), B5 (deconfliction), then the rest of B4 (requests between players and friendly
   units).
5. **A9:** AI crews and armour tactics (after your A3/A4 and A6).
6. **The tactics reels AI spec** (below).
7. **After those:** the 3D menus (the loadout editor in 3D, with buying built in and saved
   loadouts applied to units; a 3D armory; the 3D mission map; the mission UI pass), voice barks
   and voice orders, and an economy tuning pass.

## Tactics reels (Captain's training material for the AI)

Captain, who's ex-infantry, sent 23 Instagram reels (mostly thee.foxhole: Battle Drill 1 React to
Contact, Support by Fire, fire teams, and more) as "play by play the same stuff I was taught". He
wants it applied to **all AI in the game** (friendly, allied, enemy, every faction).
- **Notes:** docs/tactics/reel_notes.md. **10 of the 23 reels watched** (all thee.foxhole): Battle
  Drill 1 React to Contact, Support by Fire (shift and lift), the squad assault, Battle Drill 3
  Break Contact, near and far ambush, bunker and trench assault (SOSRA), the Russian dispersed
  attack on villages, the Soviet security zone, and fire-team and squad structure (US 9-man,
  USMC 15-man). Each reel has drill steps with frame citations, then a synthesis by echelon.
  **13 reels are unavailable:** they redirect to a removed or private profile
  (warfighterforged, "Profile isn't available"): Dekh8L_yzJq, DewwYbqx-P5, DeungvNyISp,
  DermYSIKGvs, Dehjb6qq046, DedgtmAquBm, Declmu-ySvY, DeaT_tmhFlP, DeVczxvxaZ3, DeTvbnPRZcQ,
  DeR59s_qkm5, DePKLGpFIhU, DeKGeH0xECz. Watch them if Captain gets them to you another way.
- **Frames:** contact sheets (8 frames each, 1 s steps, 0.25 s on diagrams) are kept on Captain's
  PC under B:\AI Dev Folder\tactics\frames\. They're not in this repo, because it's public and
  the frames are someone else's video. To regenerate any frame: open the reel
  (https://www.instagram.com/reel/<id>/, logged out is fine), paste docs/tactics/sheet.js into
  the page, and call `await sheet(t0, step, 8)`. Ask Captain to share the folder if you'd rather
  have the originals.
- **The reels, in order:**
  - DbUo-Cnu2CP
  - DbcX-KnOulG
  - DbrvgxcOy0V
  - DcE3Lt3Ooze
  - DcNZmXauw00
  - DdFMrP-ugvG
  - DeveKU4OUyH
  - DchFhm6uZjm
  - DavwD2dO6-A
  - DbBt61NOT3A
  - Dekh8L_yzJq
  - DewwYbqx-P5
  - DeungvNyISp
  - DermYSIKGvs
  - Dehjb6qq046
  - DedgtmAquBm
  - Declmu-ySvY
  - DeaT_tmhFlP
  - DeVczxvxaZ3
  - DeTvbnPRZcQ
  - DeR59s_qkm5
  - DePKLGpFIhU
  - DeKGeH0xECz
- **Next steps:**
  1. Finish the notes for any reels not done.
  2. Write the synthesis.
  3. Turn it into an AI spec (docs/ai_tactics.md) organised by Captain's echelons: **team 4-6,
     squad 8-12, platoon 24-48, company ~160-240, brigade = its companies plus a command
     element**. Each technique (TTP) becomes concrete behaviour: its trigger, roles, positions,
     timing, and what "done" looks like.
  4. Build it into squad_ai/tactics (team and squad) and the AI commander (platoon and up, B2),
     for every side.
- **Terror groups:** Captain wants them to start small (cells, teams, a few squads) and **grow**
  (recruits, money, weapons, territory in the living war) to field platoons or companies,
  shrinking again when they lose. Even small they're **formidable**: veteran, aggressive, local
  knowledge, ambushes, IEDs, pre-dug positions, hit-and-run. State forces (the US, Eastern
  Concord) field full echelons from the start.

## Captain's asks behind this work (so you don't need Claude's notes)

- **Armour:**
  - semi-realistic, with War Thunder-level detail and fair balance (learn from it, don't copy);
  - STANAG 4569 levels for vehicles; NIJ 0101.07 for personal armour (your 2.0);
  - composite, ERA, slat and V-hull as buyable packages with weight costs;
  - real destruction effects;
  - 1P and 3P vehicle HUDs;
  - crew roles, logistics, driving physics.
- **AI coordination** on par with HAL (Hetman Artificial Leader) for Arma 3 with LAMBS + VCOM:
  - a commander layer per side;
  - players asking friendly units for suppression, a medic, smoke or armour, and allies asking
    players back;
  - shared spot reports;
  - deconfliction;
  - common-sense real-life behaviour.
  "Very in depth: this is where our gameplay gains breadth and depth."
- **Combined arms and invasions:** government employers, ~8 km operation zones, phases and a
  moving front, staging from a friendly FOB to cut flight costs.
- **The US in the living war:** the Ashen Banner first, then the Kestrel Cartel if the US wins
  (done, D7).
- **Two high command squads from the start.** A 3D high command camera with known contacts only.
  A logical map-order HUD. Gun placement on the map with a visible cone of fire.
- **UI:** modern, common-sense and easy to use; contextual menus; the 3D loadout editor (buy
  what you don't own, save loadouts, apply them to units); a 3D armory; the 3D mission map.
- **Performance:** fixes everywhere: towns, firefights, woods and terrain, vehicles; both low FPS
  and stutters.

## How Claude ran this (so the next agent can keep the same rhythm)

- **One long-lived session per lane;** push after each phase.
- **Tests:** locally, smoke plus the phase's suites only, through
  `bash "/b/AI Dev Folder/agent-tools/run_tests_locked.sh"` (max 2 Godot runs machine-wide on
  Captain's PC; on your own machine plain tools/run_tests.sh is fine). CI runs the full set.
- **Merging:** merge into claude/ai-driving per wave. dev only moves to a CI-green commit (or one no
  worse, with flakes documented). Your review is enough sign-off.
- **Builds:** cut only at major cut points (after A5: tanks with sights and HUDs; after C3: high
  command; after D4: the first operations). Builds go to B:\Contractor\builds with Contractor.exe
  and a Discord note.
- **Writing:** "Captain" is a name, not a rank: write plainly and in a friendly tone.
