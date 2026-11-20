# Gate 2026-11-20: Fallen, security reviewer

Fallen shares Contractor's RPC layer, so Contractor's findings 1-5 apply here too (see docs/gates/contractor-security-reviewer.md on dev). The main one is the unclamped buy count: economy.gd `_rq_buy`, a Major, SUSPECTED integer overflow. The survival layer was not audited to the same depth. Read-only; nothing was run.

## Mod loading (docs/fallen_modding.md, scripts/survival/modkit.gd)
- Mods are data only: JSON files merged over the game's data, not GDScript or .pck. No `set_script` or `load_resource_pack` runs on user data.
- Manifest file names must end in .json and contain no `/` or `\` (modkit.gd:301), so path traversal is blocked.
- The doc doesn't tell players that mods can't run code. It should.
- The doc says "every player needs the same mods", but nothing checks that peers match (only `ModKit.export_card` lists them). Mismatched mods desync.

## Findings
1. **Minor, CONFIRMED: no range limits on mod values.**
   - Where: `check_file` / `validate` (modkit.gd:290-315) checks types only.
   - Abuse: a huge `n`, `count` or `pool` can loop or freeze the host. A bad mod can crash a game but can't run code.
   - Not confirmed: the schema wasn't read in full, so there may be bounds somewhere.
2. **Minor, SUSPECTED: `_server_trade` has no proximity check** (intel.gd:305-315).
   - Abuse: a client can trade with any eligible trader in `WorldSim.people()`, from anywhere.
   - Counts are checked against what each side holds (barter.gd:184-191), so this isn't a dupe.
   - Fix: require the actor to be within reach of the trader's body.
3. **Minor, CONFIRMED: map marks are uncapped, and `pos` isn't finite-checked** (survival_map.gd:150-154, 335-343, 352-355).
   - Text is cut to 80 characters, but the number of marks is unlimited. They're saved with the world, so a flood bloats the save and every map sync.
   - Fix: about 100 marks per player, plus `pos.is_finite()`.
4. **Minor, SUSPECTED: settlement actions are open to any peer with no proximity check** (settlement.gd:931-974).
   - Any peer can "order_add", "order_remove", "jobs" or "abandon". "abandon" only puts a council vote (holding.gd:1510-1514).
   - `order_remove` reads `args[0]` without a size check (a script error on empty args).
   - `WorkOrders.server_add` (work_orders.gd:59-74) doesn't cap the number of orders.
5. **Minor, CONFIRMED: inconsistent argument checks in builder `_do`** (builder.gd:1276-1331). Some actions check size and type, others don't. Whether `server_place` checks reach and ownership is unverified.

## Good
- Body actions check a 3 m reach (survival.gd:1121).
- Fieldwork finite-checks `at` (fieldwork.gd:250).
- The dev kit and DevTools are gated.

## Not checked
The world-sim save loader; virtualizer `str_to_var` (virtualizer.gd:953, 1174, 1442); `Body.server_action`; the council vote RPCs; survivors_layer `request_talk`; late-join.

## Summary
- No code execution: mods are JSON-only and path traversal is blocked; saves are shape-checked.
- The gaps are co-op griefing and save bloat: remote barter, uncapped marks and orders, no range limits on mod data.
- Document that mods are data-only, add a peer mod-match check, and audit the WorldSim save loader and `str_to_var`.
