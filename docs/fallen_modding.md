# Modding Contractor: Fallen

Call 127: everything Fallen's world is made of that can be data is data, with a documented schema
and a mod folder that changes it. The schema is `data/fallen_mod_schema.json`; the loader is
`ModKit` (scripts/survival/modkit.gd); the checker is `tools/fallen_modkit/validate.py`.

## 1. A mod

A mod is a folder with a `mod.json` and its data files:

```
user://mods/better_tins/          (the player's mods; res://mods/<name>/ ships with the game)
  mod.json
  items.json
  zombies.json
```

`mod.json`:

```json
{"name": "Better Tins", "version": "1.0", "files": ["items.json", "zombies.json"],
 "load_order": 100, "description": "Bigger tins, a slower walker.", "author": "you"}
```

| Field | Type | |
|---|---|---|
| name | string | required |
| version | string | required |
| files | array of file names | required: each `<kind>.json` beside mod.json (the kinds below) |
| load_order | int | lower loads first (default 100); then by name. A later mod wins a clash. |
| description, author | string | optional |

`user://` is Godot's user folder (on Windows `%APPDATA%\Godot\app_userdata\Contractor\`).

Mods load when a survival world starts or continues (and on every peer's zone); a mod with a
problem is skipped and its problems logged. In co-op every player needs the same mods.

## 2. How a file merges

Each file is merged over the game's own data **by id**:

- objects merge key by key, deep; a key set to `null` is removed;
- a list of records that all have an `"id"` merges by id (a matching id is patched field by field,
  a new id is added, `"remove": true` removes it);
- any other list of objects is added to (a topic's lines);
- anything else (numbers, strings, lists of numbers or pairs) is replaced.

A record whose id is already in the game is a **patch**: give only what changes. A new id needs
every required field.

## 3. The files

Types: string, int, number, bool, array, dict. "Refs" are item ids that must exist (the game's or
the mod's own `items.json`).

### items.json — `{"items": [ ... ]}` (base data/items.json)

| Field | Type | |
|---|---|---|
| id, name, type | string | required (type: weapon, ammo, magazine, medical, food, utility, misc, clothing, ...) |
| volume_l, mass_kg | number | required |
| desc | string | required |
| uses | array of strings | required |
| slot | string | optional (primary, sidearm, ...) |
| tags | array | optional |
| stats | dict | optional (the item's own numbers: rarity, melee, calibre, warmth, ...) |
| stack | int; capacity_l number; two_handed bool | optional |

```json
{"items": [{"id": "canned_meat", "name": "Tinned Meat"},
           {"id": "lucky_charm", "name": "Lucky Charm", "type": "misc", "volume_l": 0.01, "mass_kg": 0.01,
            "desc": "A rabbit's foot on a chain.", "uses": ["Carry it."]}]}
```

### zombies.json — `{"kinds": {id: kind}}` (base: the code's `ZombieAI.KINDS`)

| Field | Type | |
|---|---|---|
| walk, chase | number | required: speeds as a share of the run |
| sprint | bool | required |
| pool | number | required: how much it takes to put down |
| scream, low, trip, armoured | bool | optional: the specials' behaviours |
| share | number | optional: for a new kind, its share of the spawns (0.05 = 5%) |

```json
{"kinds": {"shambler": {"walk": 0.2, "chase": 0.3, "sprint": false, "pool": 15.0, "share": 0.05},
           "runner": {"chase": 0.9}}}
```

### perks.json — `{"perks": {id: perk}}` (base: `Perks.ALL`)

`name`, `text` (string), `fx` (dict: the effect keys the RPG layer reads: carry_kg, step_noise,
cold, build_time, treat_time, search_time, xp, melee_stamina, parry, ...) required; `needs`
({line: level}), `later` (bool) optional.

### backgrounds.json — `{"backgrounds": {...}, "flaws": {...}}` (base: `Backgrounds.ALL`, `.FLAWS`)

A background: `name`, `lines` ({line: levels}), `line` (who they were) required; `perk` optional.
A flaw: `name`, `points` (int 1-3), `text` required; `fx`, `later` optional.

### survival_recipes.json — `{"recipes": {id: recipe}}`

`name`, `inputs` ([[item, n], ...]: refs), `station` (hands, workbench, campfire, ...), `time_s`,
`output` ([item, n]: ref) required; `tool` (array), `line`, `level`, `xp`, `treat_water` optional.

```json
{"recipes": {"rag_torch": {"name": "Rag torch", "inputs": [["cloth_rag", 2], ["wood_stick", 1]], "station": "hands",
  "time_s": 5.0, "line": "fieldcraft", "level": 0, "xp": 4, "tool": [], "output": ["torch", 1]}}}
```

### survival_regions.json — `{"regions", "types", "zones"}`

- a region: `name`, `climate`, `dead` (density x), `kinds` ({group kind: share}: settlers, raiders,
  scavengers, cultists) required; `yield`, `water`, `loot` ({food, water, ammo, ...: x}),
  `unheld` optional. **Group kinds and goals** are tuned here: the kinds' shares per region; the
  goals' own numbers (noise, work time) are code (`WorldGoals.NOISE`, `WORK_TICKS`).
- a zone type: `dead` required, `evac` optional; a zone: `region`, `type` required.

### survival_fauna.json — `{"species": {...}}`

`name`, `kind` (prey, predator, bird, ...), `hp`, `speed` required; `herd`, `groups`, `run`,
`fear_living_m`, `fear_dead_m`, `meat`, `hide`, `habitat`, `seasons`, `size`, `colour`, `bite`,
`turns` optional. (Its `butcher`, `fish`, `infected` blocks merge as plain objects.)

### survival_flora.json — `{"forage", "trees", "poisons"}`

forage: `name`, `on` (ground kinds), `share`, `item` (ref) required; `seasons`, `n`,
`regrow_days`, `looks_like`, `tell`, `poison`, `stings` optional. trees: `name`, `fell_s`, `share`
required; `planks`, `firewood`, `noise_m`, `fruit`, `fruit_seasons`, `fruit_n` optional. poisons:
`name`, `hours` required; `trauma`, `line` optional.

### survival_lines.json — `{"topics": {topic: [line, ...]}}`

A line: `text` required ({name} {first} {want} {zone} {background} {item} fill in); `voice`,
`voice_text`, `speaker` ({kind, sex, age}), `tags` optional. A mod's lines are **added** to a topic.

```json
{"topics": {"greet": [{"text": "Keep your hands where I can see them, {first}.", "tags": ["scared"]}]}}
```

### arche_trail.json — `{"pieces": [...], "site_kinds": {...}}`

A piece: `id`, `kind`, `title`, `text` required; `site`, `theory`, `code` optional. A site kind:
`name` required; `zone_type`, `count`, `regions` optional.

### bunkers.json and loot_tables.json — loot tables

A table: `{"common": [bundle, ...], "uncommon": ..., "rare": ..., "very_rare": ...}`; a bundle is
`[[item, count], [item, min, max], ...]` (refs). loot_tables.json also has `pools` (`table`,
`tier_weights`). The other keys of both files (bunker counts, chances) merge as plain values.

### survival_events.json — `{"kinds": {kind: event}}` (docs/survival_events.md)

`weight`, `window_h`, `text` required; the kind's own numbers optional (pressure, rolls, loot
rows `[[item, min, max], ...]` (refs), richness, ambush_chance, crew, ring_s, glow_links, the
outcome lines). Also `chance_per_day` and `world_mult` at the top.

```json
{"chance_per_day": 0.5, "kinds": {"supply_drop": {"weight": 5, "loot": [["mre", 2, 4], ["antibiotics", 1, 2]]}}}
```

### Music and voices (manifests, by folder)

Not merged files: the music cues are files named for the cue under `data/music/`
(`stinger_first_night`, `stinger_death`, `stinger_evac`, ...: `MusicMoments`), the voices clips
under `assets/voices/survival/<voice set>/<topic>_<NN>` (a line's `voice`). A mod's own music and
voice folders are **not loaded yet** (later: `ModKit` reading `music/` and `voices/` in a mod).

## 4. Checking a mod

```
python3 tools/fallen_modkit/validate.py path/to/my_mod      # PASS or FAIL with each problem
python3 tools/fallen_modkit/validate.py --shipped           # the game's own files
```

It reads the same schema the game does; unknown fields are warnings. In game, `ModKit.errors`
lists the mods skipped and why.

## 5. World cards

A world's seed and options as a small JSON, to share a world:

```json
{"card": "fallen_world_card", "version": 1, "name": "the long winter", "seed": 4242,
 "options": {"goal": "evac", "dead": "high", "loot": "low", "needs": "normal", "world": "normal",
             "season": "winter", "join": "farm"},
 "mods": ["Better Tins 1.0"]}
```

`ModKit.export_card()` writes the world being played to `user://world_cards/<name>.json` (a dev
call); New world's **Import card** reads one from the clipboard, else the newest in that folder,
and fills the name, seed and options (it says which of the card's mods aren't on).
