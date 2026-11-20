# Gate 2026-11-20: Contractor, security reviewer

Scope: net.gd, the economy, base_hub and contracts RPCs, a sample of the soldier/vehicle/combat/ui RPCs, and the campaign and zone save loaders. There are about 198 any_peer RPCs: about 25 handlers were read in full, the rest spot-checked by signature. Read-only; nothing was run.

**The RPC surface is hardened overall.** Handlers check the sender (`_from_owner`, `get_remote_sender_id() != 1`), finite-check floats and type-check arguments (contracts.gd:1473-1497, A1-05). Saves are shape-checked. No remote code execution path was found.

## Findings, most severe first

1. **Major, SUSPECTED: integer overflow in buy.**
   - Where: economy.gd:791-794 (`_rq_buy`), base_hub.gd:3496-3497 ("buy").
   - Abuse: a `count` near 2^63/price wraps `price * count` (economy.gd:564) to a small positive number. `spend()` only rejects negative totals (economy.gd:199), so the host banks a huge stack (economy.gd:568-569) and `purchase_sink` does a huge amount of work.
   - Sell already clamps `count` to 1..50 (economy.gd:750, 761); buy doesn't.
   - Fix: clamp `count` to 1..50 in `_rq_buy` and `server_buy` (economy.gd:560, base_hub.gd:2766).
2. **Minor, CONFIRMED: no join authentication, and the build check is advisory.**
   - Where: net.gd:122-146.
   - Abuse: anyone who reaches UDP 24680 can fill the 3 slots (net.gd:60). A client that never sends `_hello`, or sends an empty commit, only produces a host warning (net.gd:110-118, 135).
   - Fix: an optional host password, and kick a peer that hasn't said hello after HELLO_WAIT_S.
3. **Minor, CONFIRMED: any peer at the base can spend company money or change the roster.**
   - Where: base_hub.gd:3473-3497: "hire", "medbay", "pick", "role", "certify_hx1", "buy". "deploy" and "release" are host-only.
   - This is a design call: should money actions be host-only too?
4. **Minor, SUSPECTED: no rate limits anywhere.**
   - Abuse: spamming any reliable RPC can lag the host. map_markers.gd:158 caps neither text length nor marker count.
   - Fix: per-peer token buckets and caps.
5. **Minor, SUSPECTED: `str_to_var` on save data** (base_hub.gd:333, scenario_checkpoint.gd:136). It doesn't instantiate objects, and the result is used only if it's a Dictionary. A hand-edited save can feed odd values to `vitals.server_restore`, but this isn't code execution.

## Checked and fine
- Campaign and zone saves: `JSON.parse_string`, then version and shape checks; bad files are set aside, not deleted (campaign.gd:113-176, game_state.gd:292-330).
- `campaign_id` is the fixed `"campaign_01"` (campaign.gd:42).
- Debug RPCs are gated by DevTools (soldier.gd:2269).
- No `load()` of user paths, no `load_resource_pack`, and no mod loader in this checkout.

## Not checked
- Late-join state replication; the full inventory and loot RPCs (loot dupes); the rest of vehicle.gd; supports; `Income.server_request`; the `request_broker` bodies; whether DevTools is off in release builds.
- ENet traffic has no DTLS: it is sent unencrypted.

## Summary
- No remote code execution and no Blocker. The RPC layer is consistently sender-checked and type-checked.
- Fix the unclamped buy count first; add a join password and rate limits second.
- Late-join, loot dupes and vehicles are unverified.
