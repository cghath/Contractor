# Contractor: polish director gate (feel + sound)

Judged from code and data only; nothing was played. Not read (unverified): vehicle_camera, animation blending, the HUD damage shader beyond its uniforms, callout levels.

## Findings

**Major**
1. Camera shake is only for blasts. Callers: demolitions.gd:654, throwables.gd:262, warheads.gd:581, launcher_sight.gd:99, vehicle_fx.gd:777. I found no view kick or shake when the player is hit by a round (searched scripts for shake/flinch/hit-marker). Taking a bullet has only the wound model and the tunnel shader (hud.gd:92-101). Fix: on a hit to the local body, a 100 ms directional view kick (1-2 deg, ease-out, scaled by energy) and a brief SFX-bus duck (-6 dB, 150 ms). Effort S.
2. The shake is white noise: player_input.gd:542-544 sets h/v_offset to randf each frame (x0.08), decaying linearly at 1.5/s. Reads as jitter, not weight. Fix: trauma squared, low-frequency noise (about 12 Hz), exponential decay about 0.5 s, a little roll. Effort S.
3. Most non-gun sounds are generated placeholders. Only shot_* (CC0 recordings, audio/sfx/CREDITS.md) and steps_soft/steps_hard are real (audio/sfx listing). Synth only (data/sounds.json): impact_body/dirt/plate, explosion, flashbang, every reload, engines, tracks, ricochet, impact_clang/thud/clank, pen_boom, detonation, tow, fire_roar, breath_dying, door_kick. Synth rate is 22050 Hz (sfx.gd:23): nothing above 11 kHz. Explosions and engines are the best swaps. Effort L to source, S per sound to drop in.
4. Flesh impact is the weakest hit feedback: impact_body is 0.16 s, -6 dB, range 30 m (sounds.json), one sound for every caliber and part. Fix: 3 real wet-impact recordings scaled by caliber, plus a distinct head hit. Effort M.

**Minor**
5. Duplicate JSON keys shot_shotgun and shot_shotgun_far in data/sounds.json with different values; the later silently wins. Delete one.
6. Engine speed smoothing is a per-frame lerp of 0.1 (sfx.gd, _update_engines): frame-rate dependent. Use 1-exp(-k*dt).
7. Engine pitch/volume is linear in speed over ENGINE_TOP_SPEED 20 (sfx.gd:87): no gear steps or load. Add shift dips (150 ms, -3 dB, -8% pitch).
8. Not found in sounds.json or Sfx callers (unverified: may exist elsewhere): player pain/hit grunt, jump and land, weapon switch, dry-fire click, shell casings, grenade bounce, door open, glass, vehicle collision.
9. Deafness is a Master low-pass 600 Hz, -12 dB (player_input.gd:238-239, 769-772) plus a text flash. Missing: ring tone and a 300-500 ms ramp in and out; the switch is instant.
10. Several mix numbers have no stated basis (STEP_OTHERS_DB, kit_rattle -20 dB, crack volume 3 to -6 dB in sfx.gd hear_shot). Unverified in play.

## Good (read)
- Recoil scaled by weapon, stance, grip, halved on ADS, with heat and settle (soldier.gd:919-926); viewmodel kick back (player_input.gd:805-809, 1241).
- Distance model: near/far variants, speed-of-sound delay, supersonic crack within 10 m (sfx.gd:359-375).
- ADS and sprint ramps are documented and tuned (movement_rules.gd:55, 88-101).
- Interior engine bus for vehicle crew (sfx.gd, _update_engines).

## What's missing / not done yet
- Damage-received feedback: view kick, direction cue, pain voice.
- Shooter-side flesh hit confirmation beyond the impact sound.
- Real recordings for vehicles, explosions, reloads, impacts.
- Written mix targets; no level was verified by ear.
- Hit-stop is not used anywhere I found; keep it off guns, consider it only for heavy melee in Fallen.
