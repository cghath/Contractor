# Contractor: Fallen: audio

Calls 63 ("diegetic plus a dynamic tension layer"), 76 (a bigger, better TTS) and 142 (a tension
toggle, subtitles for every bark). Built 2026-10-26 on `claude/survival-audio`. Every number here
is **Proposed**.

## Where the build is

- Built: the soundscape, the tension layer, music moments, the voice line pipeline (keys,
  speakers, playback with subtitle fallback, talkativeness, the renderer with three engines and
  a dry run). Suite: `fallenaudio` (headless: the logic, not the sound).
- **No clips are rendered yet** (the dev PC was busy: no models downloaded, no TTS run). Every
  line plays as a subtitle until the Captain runs the renderer (below).
- Music cues are placeholder tunes until files land in `data/music/`.

## The parts

`FallenAudio` (scripts/survival/fallen_audio.gd) is one node per survival level on every peer,
installed by `Survival._process`, for this peer's own survivor. Every 0.25 s it snapshots what's
around you (`gather`) and runs:

| Part | Script | What |
|---|---|---|
| Soundscape | `Soundscape` | wind by weather (DayNight wind_mps) and region exposure, quieter indoors; rain (on the roof indoors); the crowd's groans (ZoneDead heads within 250 m, nearer ones weigh more) played from their bearing; the settlement's hum when powered (Infrastructure) and you're inside it; your breathing (movement stamina < 0.3 or sleep < 30) and shivering (core under Needs.SHIVER_C); birds by day and dry, quiet for 40 s after the dead, a crowd head or a living stranger comes within 30 m |
| Tension | `Tension` | calm / unease / alert / danger from the dead within 60 m: suspicious or any awareness ≥ 0.1, or 3 close = unease; ALERT, SEARCHING or awareness ≥ ZombieAI.ALERT_AT = alert; CHASE or a scream in the last 8 s = danger; a horde within 120 m or a raid = danger, a horde in the zone = unease; the bite's fever = unease, delirium = alert. Up at once, down one level per 8 s quiet; volumes glide over 2 s. Drone 0 / 0.3 / 0.55 / 0.8, heartbeat 0 / 0 / 0.35 / 0.8 at 60 / 70 / 96 / 128 bpm |
| Music | `MusicMoments` | no combat music. A settlement loop (radio set in the stores or yours on, or a member with the `guitar` trait or a guitar in their kit) by morale (warm ≥ 65, low < 35, else steady), only while tension is calm or unease. Stingers once per world: the first night survived (06:00 on day 2), the evac reached, the spring thaw; a death each time (30 s apart) |
| Voice | `VoiceLines` | people's lines voiced from their clip (Callouts._show, "people" lines in a survival level), the subtitle always; radio broadcasts (HUD flash "Radio: ...") play static and their line on the Radio bus |
| Synth | `FallenSynth` (scripts/audio) | the procedural loops and stingers, built once and cached |

Footsteps by surface stay Sfx's own (every peer).

## Buses

```
Master
├── World      soundscape (wind, rain, groans, hum, breath, shiver, birds); follows the "effects" slider
├── Tension    drone + heartbeat, -10 dB under the slider (near-subliminal); muted by the toggle
├── Voice      people's lines (VoiceLines), callouts
│   ├── Radio      broadcasts, far squadmates (Sfx)
│   └── Intercom   (Sfx)
├── Music      settlement loops, stingers (and the infil music)
└── SFX, SFX_Room, Interior (Sfx)
```

Settings (`FallenAudio.setting` / `set_setting`, saved to user://fallen_audio.cfg): `world` 1.0,
`tension` 0.7, `tension_on` true, `voice_files` true. The menu's audio page doesn't show them yet
(GameSettings isn't this lane's file): a hook for the UI pass.

## Lines and voices

Every line in data/survival_lines.json has `voice` (`<topic>_<NN>`) and `speaker` (`kind`: any,
companion, raider, enclave, radio; `sex`, `age`: any or a value). `voice_text` is what's said when
it differs from the subtitle (the radio's numbers). Lines with `{first}`/`{name}` stay subtitles;
other fills are rendered with a stand-in word ("Got it.") while the subtitle says the real one.

A speaker's voice set is `<sex>_<age band>_<k>` (young < 25, old ≥ 55; m_adult and f_adult have
3 voices, the rest 1, the radio 2), from their survivor record on the host, else the body's model
and name; the clip is `assets/voices/survival/<set>/<voice>.ogg|wav`.

Talkativeness (0..1): the record's `talkativeness`, else 0.5 with traits (hot-headed +0.15,
brave +0.1, drinker +0.1, timid -0.15, ...). Chatter (plans, "got it", how are you) is said at
that chance and never while the tension is alert or worse; urgent calls (dead spotted, refusals,
breaks, warnings) always.

## Rendering the voices (the Captain)

See docs/voice.md, "Contractor: Fallen's lines and the bigger TTS". In short: fill in
tools/voices/survival_tts.json, then `python -I tools/voices/render_survival.py --dry-run`, then
without `--dry-run` (Piper), or `--engine kokoro` / `--engine xtts --gpu` for the bigger models.
1154 clips planned across 12 voice sets (the committed manifest, tools/voices/survival_manifest.json).

## Left out

- Raiders' and the enclave's officers' lines are written and keyed but nothing calls them yet
  (their code is other lanes'); the `guitar` trait isn't rolled by SurvivorPerson yet and no guitar
  item exists (the music source reads both when they do).
- Settlement music and the hum read host data (Settlement): a joining client hears them only
  when it hosts. The client's tension uses what it sees (no ZombieAI on a client: distance, the
  scream meta).
- Thunder, wet footsteps, indoor reverb per room, the settings page UI.
