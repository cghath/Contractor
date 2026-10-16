# Loot window

Captain, 2026-10-15: "a loot menu that opens, kind of like Tarkov" (inspired by it).

- **Open:** interaction menu "Loot" on a body (the dead, a downed or captured enemy) or "Open
  hold" on a vehicle's cargo point opens `LootWindow` (`scripts/ui/loot_window.gd`, held by the
  HUD as `hud.loot_window`). "Loot all" stays as the quick strip.
- **Two panes:** left = them (worn gear, carrier pouches, vest, pockets, pack; or the hold),
  right = you. Click a tile or drag it across to move it; tooltips are the item info; "Take all
  ammo", "Take all meds" and "Take everything" buttons.
- **Search time** (`Soldier.loot_search_seconds`): 1.5 s a dead body, 2.5 s a downed or captured
  enemy, 3 s a vehicle hold; contents stay hidden until it ends, a place searched once opens
  instantly. The host enforces it.
- **Closes** (Esc/Tab, or `LootWindow.why_close`) on walking out of reach (measured to
  `Soldier.body_point()`, `Vehicle.in_reach`), being hit (pain or wound count up), the target going
  or you going down.
- **Co-op:** the window only sends host requests: `_server_loot_open`, `_server_loot_move`
  (them to you), `_server_loot_put` (you to them), `_server_loot_take_class`, `_server_loot_close`.
  Each re-checks reach, the search session and that the item at that spot is still the one
  the player saw, then moves it in one host step, so two players at one body never duplicate
  anything. Peers see changes through the inventories' normal replication.
- **Not done:** the FOB arsenal stash does not use it yet.
- **World caches** (Captain, 2026-10-16, follow-up to the Red Mesa world-feel pass): `WorldCache`
  (`scripts/world/world_cache.gd`) is a crate out in the open terrain (ZoneScatter's VALUABLE
  sites, `WorldValuables`) that opens through this same window, like a vehicle's hold — the same
  `cargo()`/`in_reach()`/`server_load()`/`server_unload()` interface `Vehicle` offers, so
  `LootWindow` and `Soldier`'s loot RPCs (`_loot_target`, `_server_loot_move`/`_put`/
  `_take_class`) treat it as a third case alongside a body and a vehicle hold, not a parallel
  system. Spawned through the zone's `CacheSpawner` (`ZoneLevel._make_cache`) so a late joiner
  gets it too; its contents are rolled fresh each time the zone hosts, not saved across a reload.
- Tests: `tests/interaction_test.gd` ("The loot window"), `tests/ui_test.gd` ("loot window" fit).
