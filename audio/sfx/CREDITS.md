# Sound credits

## Gunshots: The Free Firearm Sound Library

The `shot_*.wav` recordings in this folder are cut from **The Free Firearm Sound Library**
("Prepared SFX Library", the Free Firearm SFX project, freefirearmsfx.com), released under
**CC0 1.0** (public domain dedication: "CC0 NO RIGHTS RESERVED"; free for any use, no credit
required). We credit them anyway, with thanks.

- Source: https://opengameart.org/content/the-free-firearm-sound-library
- License: https://creativecommons.org/publicdomain/zero/1.0/
- Project site (archived): https://web.archive.org/web/20141217041948/http://freefirearmsfx.com/

What each file is cut from (near take -> `shot_<family>.wav`, mid-distance take -> `shot_<family>_far.wav`;
trimmed, mono, faded, normalised; `m2` and `dshk` pitched down 20% and driven harder):

| Family | Weapons in game | Recording |
|---|---|---|
| ar, saw | M4A1, Mk18, M27, HK416, L85A2, C8, M249 | AR-15 (D_32P / D_24P) |
| akm, ak74, rpk | AKM, AK-74, RPK | AK-47 (C_28P / C_31P) |
| svd, pkm | SVD, PKM | Mosin Nagant 7.62x54R (M_21P / M_26P) |
| nato762 | M110 | Springfield 1917 .30-06 (B_24P / B_16P) |
| m240 | M240B, M240 coax/H | Arisaka (E_25P / E_18P) |
| pistol | M17 | Walther PPQ 9mm (X_39P / X_31P) |
| m2 | M2 .50 cal | Springfield 1917, pitched down |
| dshk | DShK | Mosin Nagant, pitched down |
| mosin | Mosin-Nagant 91/30 | Mosin Nagant 7.62x54R (M_21P / M_26P; the library has only this one take, same as svd/pkm) |
| springfield_hs | Springfield Heatseeker | Tikka Model T3 .30-06 (W_29P / W_24P): a modern bolt-action precision rifle, the real thematic match for this one (not a WWII rifle like the other folders) |

Everything else in the game's sound is generated in code (autoload/sfx.gd, data/sounds.json).

## Voices: Piper text-to-speech

Callouts in `audio/callouts/` (squad lines, screams, enemy chatter) are generated with
**Piper** (https://github.com/rhasspy/piper, MIT licence) from these voice models
(https://huggingface.co/rhasspy/piper-voices):

| Folder | Voice model | Dataset licence |
|---|---|---|
| v0-v3, female/v0-v1 | en_US-libritts_r-medium (speakers 27, 22, 44, 114; 37, 54) | **CC BY 4.0**: LibriTTS-R, Koizumi et al., http://www.openslr.org/141/ |
| v4 | en_US-joe-medium | CC0 |
| v5 | en_US-john-medium | public domain |
| v6-v7, female/v2-v3 | en_GB-vctk-medium (speakers 71, 60; 45, 36) | **CC BY 4.0**: CSTR VCTK Corpus, University of Edinburgh |
| ru/v0, ru/v1 | ru_RU-denis-medium, ru_RU-dmitri-medium | CC0 |
| fa/v0 | fa_IR-amir-medium | CC0 |

Lines and translations are ours (tools/voices/gen_callouts.py; speakers picked by pitch with tools/voices/pick_voices.py; gunshots cut by tools/voices/make_shots.py).
