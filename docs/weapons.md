# Weapons (pack 1: stand-ins)

Captain, 2026-10-15: "weapon variety is needed too to a small extent, we need aks, rpks, etc for
now as stand ins and some more blufor weapons as well". Pack 1 adds guns with real-world-correct
stats and simple voxel models, inspired by how other tactical shooters field an opposing force.
Everything is data in `data/items.json`, `data/rounds.json`, `data/prices.json`.

## Ammo

| Item | Holds | Round (data/rounds.json) | Calibre key |
|---|---|---|---|
| `mag_762x39` | 30 | 7.62x39 mild steel core (RF1, intermediate) | 7.62x39 |
| `mag_rpk40` | 40 | same | 7.62x39 |
| `mag_545` | 30 | 5.45x39 7N6 steel core (RF2, drops to RF1 below 700 m/s; like M855) | 5.45 |
| `mag_svd` | 10 | 7.62x54R LPS (RF2, full power) | 7.62x54R |
| `belt_762x54r` | 100 | 7.62x54R LPS | 7.62x54R |
| `box_556` | 200 | 5.56 M855 | 5.56 |
| `belt_762x51` | 100 | 7.62x51 M80 | 7.62 |

Loose rounds: `rounds_762x39`, `rounds_545`, `rounds_762x54r` (the others already existed).
Calibre keys decide which loose rounds fill which magazine, so 7.62x39, 7.62x51 and 7.62x54R never
mix. The AK, SVD and M27/HK416/L85A2/C8 magazines go in the single and double mag pouches; belts
and boxes ride in the pack. A gun takes exactly one ammo item (`stats.ammo`): the RPK takes its
40-round magazine, not AK 30s (a 75-round drum is not added yet).

Armor and vehicles follow the existing rules, nothing new: a light RF1 plate (NIJ 0101.07) stops AK and 7.62 ball and far
5.56; close M855 and 5.45 steel core defeat it, ceramic RF3 stops all of these, and
vehicle armor is only a threat to 7.62x54R and above (`round_tiers` in `data/vehicles.json`), so the
PKM and SVD can hurt vehicles and the AKs, M249 and M240B cannot.

## Guns

OPFOR: `akm` (7.62x39), `ak74` (5.45x39), `rpk` (7.62x39, 40 rd), `pkm` (7.62x54R belt),
`svd` (7.62x54R, 10 rd, comes with a 4x sight). BLUFOR: `m249` (5.56 box), `m240b` (7.62x51 belt),
`m27`, `hk416`, `l85a2` (GB), `c8` (Canada). AKs and the PKM have no rail (irons). Machine guns are
full auto only; reloads take 6.5-7 s (a new box).

Models: `stats.model_style` ("ak" or "mg") picks a silhouette in `VoxelArt` (`_rifle_ak`,
`_rifle_mg`); without it a rifle uses the AR shape, sized by `size_m`. Wood furniture uses the
new `C.WOOD`/`C.WOOD_DARK` palette slots.

## Who carries what

- Hostile faction: `CompoundLevel.HOSTILE_LOADOUT` is the AKM kit; `hostile_loadout(i)` gives the
  `HOSTILE_MIX` (AKM, AK-74, AKM, RPK, AK-74, SVD, AKM, PKM). Used by the compound's hostiles,
  zone garrisons, patrols, hunter teams and reinforcement waves. Their loot is their whole kit.
- Roles (`data/roles.json`): autorifleman = M249 + 3 boxes; the team leader keeps the M4A1. Others unchanged.
- Shop and arsenal list every priced item automatically (`data/prices.json`).

Test: `tests/weapons_test.gd` (suite `weapons`).
