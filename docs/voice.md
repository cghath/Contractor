# Voice: barks and voice orders

The Captain's immersion backlog (2026-10-16): context-aware barks and orders by voice, "nothing
insane". Built 2026-10-22 on claude/voice-economy. Every number here is Proposed.

## Barks (scripts/ui/callouts.gd)

Squadmates, allies and enemies call out what is happening. The host decides what is said; each
peer on the speaker's side shows it as a subtitle and plays its clip when there is one. Enemies
are heard in their own tongue and never subtitled. A high command squad's men are heard only
within 50 m (their squad's reports go over the company net).

| Bark | When | Line |
|---|---|---|
| Contact | the first to see an enemy (the reels' contact report: clock, distance, what) | "Contact, two o'clock, 80 m, three men, MG" |
| Reloading | a reload; the last magazine says so | "Reloading!", "Last mag for the gun!" |
| Moving / Covering / Set | bounding in contact; a base set | "Moving!", "Covering!", "Set!" |
| Man down | a squadmate goes down | "Man down! Charlie is down" |
| Frag / smoke / flash out | a throw | "Frag out!" |
| **Grenade!** (new) | a live frag or flash lands within 12 m, 1.8 s before it goes off: the nearest of the side it threatens | "Grenade!" |
| **Suppressed** (new) | suppression passes the pinned mark; where it comes from when the threat is fresh | "Pinned down! Fire from the left!" |
| **Enemy down** (new) | an AI's shot kills an enemy; by what he was | "Enemy down!", "Gunner down!", "RPG's down!", "Sniper down!" |
| **Out of ammo** (new) | in contact, nothing left for the gun in hand | "I'm out! Need ammo!" |
| **Check fire** (new) | a friendly hits a friendly: the one hit, or the nearest who saw it | "Check fire! Check fire!" |
| **Order confirmations** (new) | a voice order's receiver | "Holding.", "Moving.", "On you." |

**No spam.** A speaker talks at most every 2 s and doesn't repeat a line within 8 s; the first
spotter of an enemy speaks and the rest of the side stays quiet for 6 s. New: **one voice at a
time per group** (a squad; a side's men in no squad share one). While someone in the group is
talking (`GROUP_GAP_S`, 0.6 s) a line waits its turn (up to 3 s) unless it outranks the one being
said, and a line already waiting goes before a newer one of no more weight. Priorities
(`Callouts.PRIORITY`): 3 cuts in on anyone (man down, Grenade!, check fire, throws, the medical
calls); 2 contact, enemy down, pinned, out of ammo, confirmations; 1 the squad leader's tactic
calls, reloading, moving, covering, set; the rest 0.

## Voice clips

Clips are Piper renders in `audio/callouts/v<k>/<id>_<n>.wav` (female voices in `female/`, enemy
tongues in `ru/` and `fa/`). Piper isn't on the dev PC now, so the new lines have no clips yet:
they show as subtitles, and `Callouts.voiced_path` falls back to the bare category's clip (a
templated id like `enemy_down_mg` to `enemy_down`), then to silence.

To render them later:

```
python -I tools/voices/gen_callouts.py --list audio/callouts > tools/voices/lines_to_render.txt
python -I tools/voices/gen_callouts.py <piper.exe> <model.onnx> audio/callouts <lang> <speaker ids> [first voice]
```

`--list` writes every line with no clip (language, id, text): 81 lines, 720 clips across the
voices on 2026-10-22. A render keeps every clip already on disk, so it only makes the missing
ones. The speakers per folder are the ones the first batch used (audio/sfx/CREDITS.md).

## Contractor: Fallen's lines and the bigger TTS (call 76)

The survival mode's lines (data/survival_lines.json) each carry a `voice` key and a `speaker`;
the game plays `assets/voices/survival/<voice set>/<voice>.ogg|wav` when it's there and shows the
subtitle always (VoiceLines; docs/survival_audio.md). To render them (from the repo root, on a PC
that isn't busy; nothing is downloaded by the script):

```
python -I tools/voices/render_survival.py --dry-run          # what it would render; writes tools/voices/survival_manifest.json
python -I tools/voices/render_survival.py                    # Piper, the config's paths (the default engine)
python -I tools/voices/render_survival.py --engine kokoro    # Kokoro-82M: pip install kokoro-onnx soundfile; model + voices files in the config
python -I tools/voices/render_survival.py --engine xtts --gpu  # XTTS-v2: pip install TTS; a reference wav per voice in refs_dir
```

Edit tools/voices/survival_tts.json first: the engine, the GPU flag, each engine's model paths, and
for each voice set (m_adult_1.. f_old_1, radio_1/2) the Piper speaker id, the Kokoro voice name and
the XTTS reference wav. Existing clips are kept (`--force` re-renders: a new engine replacing the
old). `--only greet --voices f_adult_1` renders a slice to listen to first. Lines with a name in
them stay subtitles. Commit the clips and the .import files Godot makes for them.

## Voice orders (scripts/ui/voice_commands.gd, voice_order.gd)

Hold T and say it (a typed box stands in for speech recognition until a recognizer is wired to
`VoiceOrder.run`). A phrase still maps onto the keys a player would press, so voice can't do
anything the keyboard can't.

- **More of the menu**: follow me, move here, bound there, garrison that building, clear the
  town, flank there / flank them, assault there / assault them, suppress there / suppress them,
  watch there, stand up / get low / go prone / your choice, mount up, get out (on top of the
  earlier set: hold, take cover, fall back, the clears and breaches, fire control, smoke, frag,
  modes, formations).
- **Who it's for**: a squadmate's callsign or "everyone" before the order ("Bravo, hold
  position", "everyone fall back"). Nobody named and nobody selected: the whole squad.
- **Confirmations**: the one who got it answers ("Holding.", "Suppressing!", "On you.";
  `VoiceCommands.ACKS`). Formation and status orders keep their own replies.
- **High command squads by callsign**: "Hawk two, move there", "Viper three, hold", "Hawk two,
  suppress there" (base of fire), defend, follow me, regroup, extract, attack, bound, fall back,
  report. A pointed order takes the spot under the crosshair, like the map's. "... on alpha"
  holds it for a go code. They confirm over the company net as map orders do ("Hawk 2, copy,
  moving to 041 263").
- **Go codes**: "alpha go", "go bravo", "execute charlie", "execute H hour".

Tests: `tests/voice_test.gd` (grammar, addressed orders and their confirmations, barks and their
priorities); `tests/roles_test.gd` (callout rate limits, one voice per group).
