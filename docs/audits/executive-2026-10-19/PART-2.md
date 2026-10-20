# Executive audit — Part 2 of 2

Audited October 19, 2026. Production source: local `dev`,
`68a1b8336013a8170b22d2a4b66e15a626feb84b`, unchanged from Part 1.

**Result: five additional confirmed defects, two high priority (P1) and three normal priority
(P2).** R0043 reproduces all five with six failed behavioral expectations, no fixture failures
and no script errors. Together with Part 1: **13 confirmed code findings, five P1 and eight P2.**

## Scope

Part 2 follows the new combat/AI and equipment paths: suppression, spotting and weapon reach,
garrison behavior, squad/element ownership, vehicle boarding and driving, exosuit transfers,
ammo-bearer resupply, casualty claims, NVGs, attachments and controller assists. It also checks
co-op vehicle behavior, town physics/navigation performance, suite/CI parity, and inert
runner/build/publisher checks. This is a risk-based executive audit, not an exhaustive proof
of every possible game state. Part 1's campaign findings remain open.

## Findings

### A2-09 — P1: taking over a casualty's heavy suit can delete it

Location: [exo_mech.gd:322](<C:/Users/My Little Pony/Documents/Contractor/scripts/combat/exo_mech.gd:322>),
[exo_mech.gd:352](<C:/Users/My Little Pony/Documents/Contractor/scripts/combat/exo_mech.gd:352>).

The ordinary parked-suit entry gate refuses an occupied exo slot. The separate "climb into
this downed pilot's suit" gate checks the casualty, reach, hands and certification but never
checks the incoming pilot's exo slot or vehicle state. An LX-3 wearer therefore passes the
gate. After the animation, `_suit_off(body)` removes the HX-1 from its old pilot, but
`actor.inventory.put_on(SLOT, ...)` returns false because the LX-3 still occupies the slot.
The return value is ignored. The HX-1's state is discarded instead of transferred or placed
in the world. A rifle put into that discarded state's rack can be lost as well.

The diagnostic uses an actual LX-3 wearer and a downed HX-1 pilot, passes the same validation
function as the interaction, awaits the actual takeover, and counts heavy suits on both
people and in the world. It does not bypass the occupied-slot validation being audited.

**Correction:** apply the incoming pilot's entry constraints before and after the wait, and
make the transfer transactional. Check equipment-placement results before consuming the old
owner's suit. Cover empty, light-frame and heavy-frame incoming slots and interrupted entry.

### A2-10 — P2: allied/company elements ordered to board from a distance do not walk over

Location: [vehicle_layer.gd:247](<C:/Users/My Little Pony/Documents/Contractor/scripts/vehicles/vehicle_layer.gd:247>),
[squad_drivers.gd:208](<C:/Users/My Little Pony/Documents/Contractor/scripts/vehicles/squad_drivers.gd:208>).

The high command supplies the element's Squad to `server_squad_mount`, but its call to
`VehicleLayer.server_board` discards that ownership. For a man outside boarding reach,
`server_board` obtains the commander's main friendly squad and sends that squad a movement
order containing the element member's name. `Squad.pick` correctly excludes soldiers owned
by another squad, so nobody receives the walk order. The boarding queue still reports
success and waits until timeout. Being already beside the door works, which is all the
existing element-mount fixture exercises.

The diagnostic creates an independent element with its man holding away from the vehicle,
issues the real high-command mount call, verifies the boarding queue accepted him, and
checks whether his brain received MOVE. This checks order delivery without depending on a
navmesh or artificially walking him to the door.

**Correction:** direct the movement order to the soldier's actual owning Squad, or carry the
element through the boarding API. Test an element initially outside boarding reach through
arrival and seating, including a vehicle that becomes full.

### A2-11 — P2: an ammo bearer turns a partially used belt into a fresh full belt

Location: [squad_ai.gd:2898](<C:/Users/My Little Pony/Documents/Contractor/scripts/ai/squad_ai.gd:2898>).

The resupply path calls `remove_one(ammo)` and then `gunner.inventory.take(ammo, 1)` without
the removed entry's state. A belt's rounds are item state; omitting them creates the default
full belt. A bearer can turn a seven-round belt into a 100-round belt by handing it over.
The destination's return value is also ignored, so a belt that does not fit is simply lost.
The ordinary player-to-player give path already preserves the state and returns the entry
if it does not fit; this AI path does neither.

The diagnostic gives a bearer exactly one belt with `rounds: 7`, confirms an eligible nearby
M240B gunner and no contact, runs the resupply method, and counts the rounds actually received.
Existing role coverage checks belt counts, not the transferred belt's contents.

**Correction:** transfer the actual entry, preserving state, and restore it to the bearer if
the destination cannot accept it. Cover partial, empty and full belts and a full recipient.

### A2-12 — P1: boarding a carer can leave their casualty claimed indefinitely

Location: [vehicle.gd:808](<C:/Users/My Little Pony/Documents/Contractor/scripts/vehicles/vehicle.gd:808>),
[squad_ai.gd:1807](<C:/Users/My Little Pony/Documents/Contractor/scripts/ai/squad_ai.gd:1807>).

Boarding disables the soldier's brain but does not end its current care job or clear the
casualty's `care_by`. `_carer_of` regards that claim as valid as long as the carer is up and
its brain still names the casualty. The new `_free_for` seat exclusion prevents selecting a
seated responder, but does not invalidate this existing claim. Other medics' `_find_casualty`
then skips the casualty because someone appears to be treating them; the disabled carer can
never finish or release the job while aboard. A wounded soldier can be left without AI care
despite a free medic beside them.

The diagnostic establishes a real care claim, boards that carer via `Vehicle.server_enter`,
and checks the backup's response. As a control, it clears only the old claim and checks the
same backup again, isolating the claim from navigation, equipment or triage eligibility.

**Correction:** relinquish care when boarding and reject a carer who cannot perform the job.
Cover a carer interrupted during approach and treatment, through a normal boarding order,
with another responder available. Preserve valid HVT handoffs and body-position rules.

### A2-13 — P2: aim slowdown reacts to neutral civilians and enemies behind walls

Location: [assists.gd:139](<C:/Users/My Little Pony/Documents/Contractor/autoload/assists.gd:139>).

The optional gamepad assist considers every standing combatant whose faction differs from
the player. Civilians use their own faction, so they attract the same slowdown as an enemy.
No visibility test is made, so an enemy behind a solid wall also slows the stick, revealing
its presence and making otherwise empty-looking directions resist turning. The setting is
off by default; the defect affects sessions where the host enables it.

The diagnostic checks an actual neutral PeopleLayer civilian, then an enemy behind a real
physics wall, independently verifies that the wall blocks `Squad.sees`, and calls the same
slowdown helper used by gamepad input. Controller hardware and rendering are not required
to establish this target-selection defect.

**Correction:** filter out noncombatants and apply a visibility test after cheap range/angle
filtering. Test visible enemies, friendly units, civilians, captives and occluded enemies.

## Runtime evidence

These run numbers use the same external `Contractor-audit-logs` parent as Part 1; they are
not the separate shared `Documents/Contractor-test-logs` counter.

### R0042 — broader checks, FAIL

[Summary](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-19/R0042-220733-FAIL-dev-68a1b83/summary.txt>).
Import passed. Eight of eleven suite families passed: smoke, net (host and client), mech,
attachments, nvg, controller, roles and casualty. Three failed:

- **Squad:** two of three AI followed the second human team leader within 30 m; the third
  remained 65.7 m away. Correct team ownership and subsequent Hold behavior passed. The
  precise cause of this formation failure remains unestablished.
- **Vehicles:** all the host's individual vehicle checks passed, but the late-join client
  failed seven assertions, including its host digest, taking the driver's seat, driving and
  manning the turret. The host consequently failed to observe client driving. Several
  assertions may cascade from one cause; they are not counted as eight diagnosed defects.
- **Town performance:** three budgets were missed. This is a release-validation concern
  independently of the five reproduced code findings above.

| Town fight measurement | R0042 | Budget | Result |
| --- | ---: | ---: | --- |
| Average physics tick, scripts plus engine | 38.888 ms | 20 ms | FAIL |
| 95th percentile tick | 57.98 ms | 40 ms | FAIL |
| Building scans per simulated second | 218 ms | 120 ms | FAIL |
| Average engine step | 2.589 ms | 6 ms | Pass |

The tick's worst sample was 643.36 ms; the per-frame engine physics monitor reached
2537.88 ms. The benchmark used its existing 42 soldiers and 900 ticks; no budgets or load
were reduced. Ragdoll settling/body placement and rebuilt voxel-navigation seams passed.
It also logged a 30.2 m detour for a 1.5 m seam crossing while the town was represented by
its streamed-out proxy; that known limitation was already noted in the earlier audit follow-up.

This is headless evidence on this machine. It establishes a budget failure, not rendered FPS
or a proven attribution of the entire overrun to one recent commit. Building scans are an
observed contributor; profiling should establish the remaining costs before changing budgets.

### R0043 — targeted confirmations and follow-up checks

[Summary](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-19/R0043-223144-FAIL-dev-68a1b83/summary.txt>),
[diagnostic output](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-19/R0043-223144-FAIL-dev-68a1b83/audit2_systems.log>).
Import passed. The six diagnostic failures reproduced the five findings above, with every
fixture/control assertion passing and no script errors:

| Finding | Observed result |
| --- | --- |
| A2-09 | No HX-1 remained on either pilot or in the world; incoming pilot still wore the LX-3. |
| A2-10 | Element member remained on HOLD (`order=1`) despite an accepted boarding queue entry. |
| A2-11 | One seven-round belt became one 100-round belt. |
| A2-12 | Backup was eligible but offered no care while `AuditCarer` retained the claim; clearing only that claim made the backup answer. |
| A2-13 | Slowdown was 0.40 for both a neutral civilian and an enemy independently confirmed hidden by a solid wall. |

Garrison, day/night and world synchronization passed, including both world peers.
The **reduced vehicle diagnostic** also passed on both peers: the host ran only its `parked`
and `fire` sections (`CONTRACTOR_VEHICLES_ONLY=parked,fire`), then the normal late-join client
checked replication, drove the vehicle and manned the turret. This proves that the fresh-range
co-op case works; it does not turn R0042's full vehicle suite green. Investigate state left by
the full host sequence, including save/reload and the newer driving tests, before attributing
all the full-run failures to the network transport or treating them as unrelated bugs.

The overall R0043 verdict is correctly **FAIL**, because its dedicated audit diagnostic
intentionally asserts the desired behavior and finds the defects. The four ordinary/follow-up
suite families passed. No production fix was applied between the runs.

Diagnostic sources are retained under R0043's `probes` folder outside the project, avoiding
normal Godot imports of audit scripts. To reproduce, copy the `.gd` and `.tscn` into `tests`
and run `tools/run_tests.sh audit2_systems` with an isolated tag, port and retained-log parent.
The script uses isolated test saves and direct fixture controls; it changes no real campaign.

## Tooling and limits

Both local tooling self-checks passed:

- [S0044: test runner checks](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-19/S0044-224105-PASS-runner-check-68a1b83>): default-suite CI coverage, failure detection, retained logs, build-error handling and concurrent run numbering passed.
- [S0045: release publisher checks](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-19/S0045-224232-PASS-publish-release-68a1b83>): public, draft, missing, error and malformed response cases passed using inert Git/GitHub test doubles. No real release was published. Runner export checks likewise used a fake exporter; they do not validate a real game build.

These checks do not establish a green full default suite or current remote CI. Rendered
performance, hands-on controller feel, remote four-player sessions and real exported builds
were not tested. Part 1's linked-zone failures and Part 2's full formation/vehicle/performance
failures remain open alongside the 13 confirmed code findings.

Only audit documents are added to the repository. Diagnostic sources and numbered logs are
retained outside it. No production code was changed, and nothing was pushed, merged or published.
