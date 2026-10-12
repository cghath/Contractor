# Sound

Captain (2026-10-12): our side owns all sound. Sounds are **generated in code, stylised to fit
our world** rather than photo-real; a real recording can replace any of them later.

## How it works

- **`Sfx`** (`autoload/sfx.gd`) plays sounds by id. **`data/sounds.json`** defines each id:
  `range_m` (heard within), `near_m` (past it the `<id>_far` variant plays), `travels` (arrives
  late at the speed of sound), `unit_size` (metres at full volume), `volume_db`,
  `pitch_spread`, and a `synth` recipe.
- **Generated sounds:** `SfxSynth.make` (`scripts/audio/sfx_synth.gd`) builds each sound from
  layers (an attack of noise, a falling tone for weight, a low-passed tail, a metallic ring,
  mechanism clicks), three variants per sound so repeats differ, made once and cached.
- **Real files win:** `res://audio/sfx/<id>.ogg`, or `<id>_1.ogg`, `<id>_2.ogg` ... for variants.
- **Every peer hears from its own listener** (the camera): near or far variant by distance,
  delayed by distance / 343 m/s, and a **crack** when a round passes within 6 m of the
  listener from a shooter more than 25 m away.
- **Ranges follow the AI's hearing:** a rifle shot 220 m (SquadAI.HEAR_SHOT_M is 200), a
  suppressed one 45 m (HEAR_SUPPRESSED_M 40). What the player hears, the AI hears.
- **Buses:** `SFX`, `SFX_Room` (a sound under a roof: reverb) and `Voice` (callouts) send to
  `Master`, whose low-pass is deafness.

## What plays where

| Sound | From |
|---|---|
| `shot_rifle`, `shot_pistol`, `shot_suppressed` (+ `_far`), `crack` | `Soldier._server_fire` -> `Sfx.server_shot` (host to every peer) |
| `impact_dirt`, `impact_plate` (plates, vehicles), `impact_body` | `CompoundLevel.show_impact` (already on every peer) |
| `explosion` (+ `_far`), `flashbang` | `CompoundLevel.show_explosion` / `show_flash` |
| `reload`, `throw` | `Soldier._server_reload` / `_server_throw` -> `Sfx.server_play` |
| `step`, `step_hard` | every peer, from how each soldier moves (no network); hard on structures and vehicles; quieter crouched |
| `engine_mrap`, `engine_soft`, `engine_ifv`, `engine_mbt`, `engine_aircraft` | every peer: loops while someone drives; pitch and volume rise with speed; picked by the vehicle's `class` in data/vehicles.json |

## Adding or changing a sound

- Tweak a recipe in `data/sounds.json`, then listen: `tools/export_sounds.gd` writes every
  sound as WAV files (run it as a numbered S run, see docs/debugging.md):
  `<godot> --headless --path . -s res://tools/export_sounds.gd -- <folder>`.
- New sound: add an id with a recipe, then call `Sfx.play_at(id, pos)` on every peer, or
  `Sfx.server_play(id, pos)` from the host. **Vehicles (cghath's side):** engine, horn, hits and
  wrecks go the same way: add ids here and call Sfx from the vehicle code.
- Tests: suite `sound`.
