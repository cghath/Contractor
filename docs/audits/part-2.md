# Audit part 2 — gameplay, AI and player interfaces

October 13, 2026. Baseline remains `dev`, `fcae676b8318b7534fdc3f2e4d17a9e9a228275f`. Part 1's findings remain open; no gameplay fixes have been applied.

Part 2 is complete: **nine actionable findings**, one high priority (P1) and eight medium priority (P2). All fourteen existing suites passed in R0004. R0005 confirmed the targeted observations below, including item duplication and three usable medical actions outside the drawing limit.

## Scope

Reviewed hit resolution and armor, wounds and the treatment interface, timed reload/treatment actions, inventory transfers and nested MOLLE containers, death/body handling, movement and stamina, squad decisions and commands, scavenging and pack recovery, civilian/HVT behavior, and the HUD, inventory, interaction and medical menus. Checked the role/item data those paths consume.

The medical review checks consistency between the game's model, AI and menus. Headless checks do not establish visual polish or control feel.

The report separates normal-suite coverage from targeted diagnostic observations. Diagnostic probes deliberately check whether a suspected bug occurs; their passing result means the problem was reproduced, not fixed.

## Findings

### A2-01 — P1: loot-all duplicates medical supplies attached to a backpack

Location: [soldier.gd:1764](<C:/Users/My Little Pony/Documents/Contractor/scripts/actors/soldier.gd:1764>), consumed by `_loot_all_at_once()` at line 1721.

`gear_entries()` copies worn gear and then separately lists every pouch container's contents. It empties the copied carrier's attachment contents to avoid counting them twice, but applies that step only to the `vest`. A backpack with an attached aid bag therefore retains the supplies in its copied state and lists the same supplies as separate entries. Loot-all transfers both representations.

The audit probe staged a backpack with an aid bag containing two pressure bandages and transferred its gear through the production loot-all helper. **It produced four bandages across the two inventories from an initial two.** The medic role includes an aid bag, so this concerns an existing loadout rather than a hypothetical item.

Recommendation: choose one representation for attachment contents during flattened transfers, for both carrier and backpack. Add a conservation check across donor and recipient, including a partially filled recipient and the rollback path. Do not change normal `strip()` packing, which intentionally carries attached contents inside their parent item.

### A2-02 — P2: an old reload can finish on a different gun of the same type

Location: [soldier.gd:717](<C:/Users/My Little Pony/Documents/Contractor/scripts/actors/soldier.gd:717>), with equipment mutations through line 849 and pickup at line 962.

The reload timer checks its serial, the soldier's condition, and the item ID still in the slot. Equipment changes do not invalidate the reload serial. Dropping an M4 during a reload and picking up another M4 therefore passes the final item-ID check even though the physical gun changed. The old timer can load the replacement gun from the player's magazines.

Recommendation: associate the reload with an equipment revision or physical item identity, and cancel it when that slot changes. Retain the existing protection against a reload crossing death/respawn. The probe uses the real drop and pickup requests and gives the replacement a distinct state marker.

### A2-03 — P2: IV placement can bypass the game's blocked-site rule

Locations: [wound_model.gd:1006](<C:/Users/My Little Pony/Documents/Contractor/scripts/combat/wounds/wound_model.gd:1006>), [wound_model.gd:1117](<C:/Users/My Little Pony/Documents/Contractor/scripts/combat/wounds/wound_model.gd:1117>), [wound_model.gd:1182](<C:/Users/My Little Pony/Documents/Contractor/scripts/combat/wounds/wound_model.gd:1182>).

The menus and `iv_site_ok()` disallow an IV below a tourniquet. The authoritative treatment check only asks whether a line already exists. `apply_item()` substitutes `iv_part()` when the requested site is invalid; if every site is blocked, `iv_part()` returns the first forearm anyway. The AI access options still include IVs in this state.

Recommendation: enforce site validity in the shared treatment check, return no IV site when none is available, and offer only usable access options to the AI. An IO option can remain available under the game's existing rules. The probe gives all four limbs effective tourniquets and checks that the model nevertheless places an IV at a rejected site.

### A2-04 — P2: temporary hearing loss can leave later sessions muffled

Location: [player_input.gd:176](<C:/Users/My Little Pony/Documents/Contractor/scripts/actors/player_input.gd:176>).

Hearing loss enables a low-pass filter and lowers volume on the global Master audio bus. The player-input node has no teardown that restores this global state. A healthy new player's `_deaf` starts false; `_update_hearing()` sees false again and returns without disabling the old filter or restoring volume. Leaving a session or changing levels while deaf can therefore carry muffled audio into the menu or replacement player.

Recommendation: give the temporary audio effect an explicit owner/lifetime, restore the previous bus state on teardown, and initialize it for each new local player. The probe applies deafness with one driver, frees it, then invokes the healthy replacement driver's hearing update and checks the global bus.

### A2-05 — P2: the medical menu truncates treatment rows without scrolling

Locations: [medical_menu.gd:456](<C:/Users/My Little Pony/Documents/Contractor/scripts/ui/medical_menu.gd:456>), [medical_menu.gd:476](<C:/Users/My Little Pony/Documents/Contractor/scripts/ui/medical_menu.gd:476>), [medical_menu.gd:510](<C:/Users/My Little Pony/Documents/Contractor/scripts/ui/medical_menu.gd:510>).

The fixed panel fits 14 treatment rows. Drawing stops at that limit, but the list can contain more and there is no scrolling or pagination. The hit-test still considers every row, including ones not drawn and outside the treatment panel. A sufficiently equipped treater can lose visible access to valid actions or click an invisible action.

Recommendation: use a scrollable treatment list with clipping, and apply the same visible range to drawing and input. Make the overall panel fit smaller windows. The probe carried the available treatment items and staged a wounded patient with an existing line. It produced **32 rows**, with the usable adenosine, burn dressing and blanket actions beyond the 14-row drawing limit. This is geometry/input evidence, not a screenshot review.

### A2-06 — P2: equipped launchers disappear from the inventory's slot controls

Location: [inventory_screen.gd:17](<C:/Users/My Little Pony/Documents/Contractor/scripts/ui/inventory_screen.gd:17>), with tile construction at line 475.

The inventory model includes a `launcher` slot and existing role kits equip launchers, but `SLOT_NAMES`, `LEFT_SLOTS` and `RIGHT_SLOTS` omit it. The screen can equip a launcher from a container or pack attachment, after which there is no loadout slot tile for selecting, inspecting, stowing or dropping that equipped launcher. Keyboard selection/drop provides a workaround but does not complete the inventory flow.

Recommendation: include the launcher in the displayed equipment slots and verify its loaded/spent state and actions. Source tracing and the probe check the actual slot lists used to create the tiles.

### A2-07 — P2: dragging a ground pack into a container swaps worn packs

Locations: [inventory_screen.gd:732](<C:/Users/My Little Pony/Documents/Contractor/scripts/ui/inventory_screen.gd:732>), [soldier.gd:962](<C:/Users/My Little Pony/Documents/Contractor/scripts/actors/soldier.gd:962>).

Every nearby-item drag destination—container, slot, attach point or soldier—calls the same pickup request and discards the destination. Picking up a pack while already wearing one always swaps the worn pack. This contradicts the pickup code's own distinction that dragging into the backpack stows it instead.

Recommendation: include the requested destination in the host request and validate it there. Keep click-to-pickup's equipment behavior separate from explicit container placement, while preserving reach, capacity and item state. The probe uses an empty assault pack that fits inside a worn rucksack, then invokes the screen's actual drag callback.

### A2-08 — P2: AI pack recovery identifies a model and location, not its own item

Locations: [squad_ai.gd:2395](<C:/Users/My Little Pony/Documents/Contractor/scripts/ai/squad_ai.gd:2395>), [squad_ai.gd:2409](<C:/Users/My Little Pony/Documents/Contractor/scripts/ai/squad_ai.gd:2409>).

Dropping a pack records only its item type and initial position. Recovery selects the nearest same-type pack within three metres of that position. Nearby squadmates commonly carry the same pack model with different contents, and dropped packs move under physics. A unit can therefore equip another squadmate's pack while leaving its own behind. If its own pack rolls outside the radius, the order is cleared without finding it.

Recommendation: retain the spawned world item's stable UID and recover that item at its current position. Handle a missing/taken pack explicitly. The probe moves the original pack slightly and places another same-model pack closer to the recorded position, using different state markers to distinguish them.

### A2-09 — P2: “Scavenge that body” searches the old capsule location

Location: [squad.gd:243](<C:/Users/My Little Pony/Documents/Contractor/scripts/ai/squad.gd:243>).

The command finds a body near the aimed point using `global_position`. A ragdoll can slide metres from that capsule; ordinary looting and the scavenger's walking target correctly use `body_point()`. Looking at the actual corpse can therefore return “Look at a body,” while aiming at the invisible old position succeeds.

Recommendation: locate the commanded corpse using `body_point()` and use the same reference for related body selection/leash checks. Preserve the documented ragdoll reach and stand-up fixes. The probe moves the ragdoll parts six metres, then compares command results at the visible body and capsule positions.

## Validation

| Run | Checks | Result |
| --- | --- | --- |
| R0004 | smoke, gameplay, wounds, armor, medical, casualty, squad, scavenge, movement, interaction, roles, logistics, animations, people | All 14 suites passed; runner result PASS. |
| R0005 | `audit_part2`: nested loot conservation, same-model weapon replacement during reload, blocked IV sites/AI options, audio lifetime, medical-row geometry, launcher slot lists, explicit ground-pack destination, AI pack identity, and displaced-body command lookup | All diagnostic observations confirmed; zero failed probe checks and no script errors; runner result PASS. These observations reproduce bugs, not fixes. |

Detailed evidence: [R0004 summary](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-13/R0004-040236-PASS-dev-fcae676/summary.txt>), [R0005 probe log](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-13/R0005-041928-PASS-dev-fcae676/audit_part2.log>).

Probe boundaries: loot uses the real internal transfer helper, reload/pickup uses a hosted player and actual requests, and AI/medical scenarios stage controlled states. The launcher result inspects the lists used by tile construction. Audio checks the actual driver's teardown and a healthy replacement driver's update. No screenshot or listening test was performed, and these targeted probes are not four-client network regressions.

All logs are retained under:

`C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs`

No production code was changed. Diagnostic scripts and their scenes live under `docs/audits`; the wrapper routes `audit_part2` through the normal retained-log runner.

## Coverage and follow-up

The reviewed design has useful shared boundaries: players and AI use the same timed treatment requests; armor damage travels with item state; casualty care and scavenging have explicit claims; movement gates stances and sprinting by wound state. The normal suites provide substantial coverage of these paths, but the findings above concern item identity, nested containers and transitions outside their current checks.

Part 3 has now resolved the three integration questions deferred here: separate-world building-cache leakage (A3-04) and blast-only civilian accounting (A3-02) were reproduced; inactive numeric doctrine tuning was confirmed by source review (A3-07). They remain separate Part 3 findings and are not counted again in Part 2. See part-3.md for performance and delivery review, and SUMMARY.md for the final readiness assessment.

Suggested fix order: nested loot conservation first; then action/item identity and shared IV validation; then UI reach/destination/list access; then audio lifetime. Verify with the relevant existing suites plus regression checks for the reproduced cases. Live playtesting remains necessary for camera/body collision, inventory drag usability, medical-menu layout and AI navigation on real terrain.
