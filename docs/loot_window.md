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
  gets it too. Its contents are rolled the first time the zone hosts; from then on the zone save
  keeps what's in it (`WorldCache.to_save`/`server_fill`, `GameState.caches`), so a looted box
  stays looted (and a strongbox opened stays open) after a reload.
- **Site boxes / compound loot** (Captain, 2026-10-16, three asks that are one mechanic; task 6 of
  the Captain's tasking, 2026-10-19): `WorldValuables.server_spawn_site_boxes` puts `WorldCache`s
  in the rooms of every hand-built module (compound, outpost, village, checkpoint, hq, qrf_base,
  comms) where that kind of thing would be, from `data/loot_tables.json`: each site type lists its
  box spots (room, position, table, label such as "Desk", "Radio desk", "Weapons crate",
  "Footlocker", "Seized goods"). The fitting rooms get a box every time (an HQ's office desk and
  radio room, a compound's command-building desk and armory crate, an outpost's bunker, a comms
  site's radio desk); a few of the rest are picked per site. Each box rolls a tier by its site's
  stated weights, then one bundle of that tier from its table:

  | Site | common | uncommon | rare | very rare | boxes |
  |---|---|---|---|---|---|
  | village | 72 | 22 | 5 | 1 | 1-3 |
  | checkpoint | 66 | 25 | 7.5 | 1.5 | 1-2 |
  | outpost | 64 | 26 | 8 | 2 | 1-3 |
  | compound | 60 | 28 | 9.5 | 2.5 | 2-4 |
  | comms | 58 | 29 | 10 | 3 | 1-2 |
  | qrf_base | 58 | 29 | 10 | 3 | 2-3 |
  | hq | 52 | 31 | 13 | 4 | 3-5, and the strongbox |
  | anything else (a generated town) | 70 | 23 | 6 | 1 | 1-3 by its loot spots |

  Very rare only in a hot zone (contract zones roll up to medium): elsewhere it counts as rare.
  Tables: office (cash, intel, valuables; gold, a laptop or a relic very rarely), radio_room
  (intel, enemy radios, electronics; a laptop, a jammer or NVGs very rarely), command_post,
  armory (mags and grenades up to an RPG-7, SVD or PKM), ammo, barracks (footlockers), medical
  (dressings up to blood and surgery kits), stores (salvage and vehicle parts), home (village
  houses), stash (contraband) and seized (a checkpoint's confiscated goods). Rolled from the
  zone's id and the module's id (`site_plan`, `roll_box`): the same zone gives the same loot on
  every visit.
- Tests: `tests/interaction_test.gd` ("The loot window"), `tests/ui_test.gd` ("loot window" fit),
  `tests/loot_test.gd` (tables, spots, fit, rarity over many seeds, same seed, saved and reloaded),
  `tests/world_test.gd` (a late joiner gets the boxes and their contents).
