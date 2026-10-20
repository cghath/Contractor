# Static weapon teams (AI bar G-25)

The Captain, 2026-10-19: "we also need static weapon teams that can move dynamically to where
they're needed", and "mortars sent to reposition for targets to be in range, setting up a gun on a
hill to suppress the enemy etc should be options for the AI factions and players."

So not guns bolted to posts. Crew-served weapons that a team of two or three carries in loads,
sets up where the fight needs them, fights from, packs up and moves again. Every side has them:
hostile, allied and rebel AI, and the company (players and squad AI). We learn from how VCOM's AI
takes up static guns and fires mortars (a "location known" score per enemy group, ranging then
fire for effect) and how LAMBS moves its groups; we take no code, only the behaviour.

Queued as step 4 of the work order in `docs/ai_bar_gaps.md`, after the P0s, G-09/G-11/G-15 (the
suppression numbers a gun team runs on) and G-17 (high ground). Every number here is Proposed.

## What is already there to build on

- **Vehicles with guns.** `Vehicle` (`scripts/vehicles/vehicle.gd`) has gun seats, a turret
  (`VehicleTurret`), belts in a cargo hold, and `AavGunner`, which mans any armed vehicle's gun
  seat for the AI (it fires at what it sees). The guns are in `data/vehicles.json` "guns":
  `m2hb`, `dshk`, `m240c`, `m240h`.
- **High ground.** `SquadTactics.overwatch_spot` (G-17) finds a spot with height and a line on
  the enemy, out of other groups' sight.
- **Fire by range and suppression by round** (G-09, G-11): a .50 suppresses 5 m out, x1.8.
- **Mortar rounds.** `RebelCalls._mortar_round` already lands a round (`Throwables.server_detonate`
  plus a crater) with a spread; the rebel mortar call-in warns, then drops rounds.
- **The enemy's picture.** `Alert` keeps a last known position whose uncertainty grows with time,
  reports travel by radio with delays, and the comms mast can go down.
- **Allied elements.** The wave 6 weapons team (M240B, an ammo bearer, two AT4s) comes in under
  the host's high command and map orders.

## Part a: the weapon itself

A static weapon is a `Vehicle` of a new kind, `static`: no wheels or engine, frozen in place, one
gunner seat (low, behind the gun), a turret with its traverse and elevation limits, belts or
rounds in a small cargo hold. Because it's a vehicle, `AavGunner` already mans it for the AI, it
takes hits like one (a wrecked gun is scrap), and players get in its seat the same way.

| Weapon | Who | Loads (kg) | Set up / pack (s) | Notes |
|---|---|---|---|---|
| M2HB on M3 tripod | company, allied | gun 38, tripod 20 | 20 / 15 | `m2hb` gun, 100-round belts |
| DShK on tripod | hostile, rebel | gun 34, mount 30 | 20 / 15 | `dshk` gun |
| M224 60 mm mortar | company, allied | tube 9, bipod + plate 12 | 25 / 15 | HE, smoke, illumination later |
| 82 mm mortar | hostile, rebel | tube 14, bipod 13, plate 15 | 30 / 20 | HE, smoke |

- **Loads are items.** Packed, a weapon is its loads (`static_m2_gun`, `static_m3_tripod`, ...),
  carried like any heavy item: they count toward weight and slow the carrier the way weight
  already does. Set it up with every load in reach: in your own inventory, or a squadmate's
  within 3 m. Packing a gun with nobody on it puts the loads back in the packers' hands (or on
  the ground when there's no room).
- **Set up:** an inventory action ("Set up the M2 here") with a short placement check: ground
  under it not too steep, nothing in the way of the barrel, not inside a wall (the defence
  placer's checks, `defence_placer.gd`, have most of this). A progress bar like other timed
  actions; moving or getting hit stops it.
- **Ammo:** belts and rounds are ordinary items. The assistant gunner carries them; a gun on the
  ground takes them from anyone beside it ("Load a belt").
- **Mortar fire:** a mortar has no line of sight. A round flies a high arc to its aim point with a
  dispersion that grows with range, lands after its flight time, and goes off like the rebel
  mortar's. Minimum and maximum range per weapon (see the calls below).

## Part b: AI gun teams

A gun team is its own small squad (G-02): a gunner, an assistant gunner with the ammo and a
rifleman for its security, the loads shared out. What it does:

1. **Moves packed** to where the fight is, with its element or on its own.
2. **Picks a gun spot** by `overwatch_spot` with a wider search (out to about 150 m from the team,
   at 150-600 m from the enemy): height over him, a line on him, out of other groups' sight, cover
   or foliage at the spot.
3. **Sets up** (the timed action), gunner on the gun, assistant beside him feeding it and
   watching, the rifleman covering the flank.
4. **Suppresses**: the gunner fires on what he sees, or on the known position (bursts, G-09). The
   gun's suppression (G-11) pins the enemy for the rest of the force to move.
5. **Moves again** when the fight leaves it: the enemy out of its sight or range for a while, the
   force moving on, or the spot under heavy fire. It packs up and goes to the next spot.

Who has them:

- **Hostile:** some garrison sites keep a gun team (not a fixed gun): it sets up on the site's best
  ground when the site is alerted, and the enemy commander (`EnemyCommand`) can send it out with a
  response. A team at a site holds with the garrison (they never sally out; Captain 2026-10-19).
- **Allied:** the wave 6 weapons team can bring an M2 instead of its M240B.
- **Rebels:** a DShK team with the "Fighters" call-in at its upgrade levels.
- **The company's squad AI:** a squadmate carrying the loads can be ordered to set up (part d).

## Part c: mortar teams

A mortar team is a gunner and an assistant (plus a third man for the 82 mm), the loads shared.

1. **A target:** the hostile one comes from `Alert`'s last known position and its uncertainty, or
   from one of its own men who sees the company (an observer). The allied and company ones come
   from a player's mark (part d).
2. **In range?** If the target is too far or inside the minimum range, the team **moves until it is
   in range**: to the nearest spot at about mid-range from the target, out of the target's sight,
   then sets up.
3. **Ranging:** one or two rounds first, landing with the target's uncertainty plus the mortar's
   dispersion. With an observer who sees the target, each round lands closer; without one, the
   rounds stay as wide as the guess.
4. **Fire for effect:** once a round lands within about 30 m of the target, four to six rounds.
5. **Stopped by comms:** with the comms mast down, a hostile mortar gets no observer corrections
   (it keeps firing on the old guess, or stops). Killing the crew or taking the mortar ends it.
6. **No friendly rounds:** no mission onto a target with its own side within 50 m of it.
   Warnings go out the way the rebel mortar's do.

## Part d: players

- **Get one:** the quartermaster sells the M2 kit and the M224, priced like the vehicles, at a
  standing tier. Loads and ammo go to the stash and into loadouts like any gear.
- **Carry and set up yourself:** carry the loads (heavy: two players or a player and a squadmate
  share them), "Set up" from the inventory, get in the gunner seat. The mortar takes a map mark: you
  mark a point on the map, it shows the range and whether it's in range, and the gunner fires.
- **Order the squad:** command menu "Weapons team" for a squadmate carrying the loads: "Set up the
  gun here" (at the point you look at), "High ground" (they pick the spot, `overwatch_spot`),
  "Suppress there", "Pack up and follow". Map orders: "Set up the gun here" and "Mortar: fire on
  this mark". The same orders go to an allied weapons team under high command.

## Order of work

1. Part a: the `static` vehicle kind, the M2 on its tripod (art, spec, seat, turret), loads as
   items, set up / pack up, ammo; a test that sets it up, mans it and fires it.
2. Part b: the AI gun team (spot, set up, suppress, move on), hostile first, then the allied and
   rebel ones; a test with a team taking high ground and suppressing.
3. Part c: mortars (the 60 mm and 82 mm, the arc and dispersion, ranging, moving into range); a
   test where a mortar out of range moves, sets up and ranges in.
4. Part d: the player's side: buying, carrying and setting up, the command menu and map orders.
5. The DShK and the 82 mm: the same work for the other side's weapons.

## Status (2026-10-20, branch claude/ai-driving)

- **Part a, done.** The M2 on its M3 tripod and a DShK on a tripod: `Vehicle` kind `static` (frozen,
  one gunner seat, `AavGunner` mans it), loads as two-handed items (real weights), set up / pack up
  (`StaticWeapons`), belts the crew carries loaded on set-up.
- **Part b, done.** `GunTeam`: carries the gun to high ground in defilade (against every enemy it
  knows, a flank counts against a spot), faces the threat, sets up, digs a parapet in front, mans
  it; packs up and moves on when the fight leaves it or fire from a flank keeps catching it.
  Garrisons at HQs, QRF bases and half the compounds and outposts keep a DShK team that sets up
  inside the site once its ambush is sprung.
- **Part c, done.** `MortarFire` (rounds in flight, dispersion, HE bursts) and `MortarTeam`: picks a
  spot in range and out of the target's sight, ranges in (errors halve when one of its side sees
  the round land; the enemy's need their comms), fires for effect, waits; never danger close.
  The M224 (60 mm) and the 2B14 (82 mm), real weights and ranges. HQs and QRF bases keep a 2B14
  team that sets up once the site is alerted.
- **Part d, done (first pass).** The mortar laid and fired by hand from its firing table
  (`MortarPanel`, `MortarTable`; rounds from the hold or the player's kit). Command menu, Action >
  Weapons team: set up the gun there, set up on high ground, mortar fire on a point, pack up and
  follow. Buying: the M2's and the M224's loads and 60 mm rounds are for sale (priced).
- **Allied and rebel teams, done.** The allied weapons team brings an M2 (its gunner and ammo
  bearer carry it as a gun team inside the element); the rebels' Fighters call-in, upgraded, brings
  a DShK the same way (StaticWeapons.arm_gun_team).
- **Still to do.** Map orders for weapons teams; a mortar sound of its own (it uses the far
  explosion); grenade launchers (Mk19, AGS-17).

## The Captain's calls (2026-10-19)

1. **Weapons first: as proposed.** The M2 and DShK, the M224 60 mm and 82 mm mortars; grenade
   launchers (Mk19, AGS-17) later.
2. **Weights: real.** An M2 is 38 kg plus a 20 kg tripod: a two-man carry that slows you down.
3. **Mortar ranges: real.** 60 mm about 70-3,500 m, 82 mm about 85-4,000 m. On our zones a mortar
   reaches most of the map, so it moves mainly for the minimum range, for a hot zone's 4 km, and to
   get out of the enemy's sight or counter-fire; its spread grows with range, so a closer spot is
   still a better one.
4. **Player mortar aiming: manual tables.** No worked-out solution: the player reads the range
   (and the height difference) off the map, looks up elevation and charge in the weapon's firing
   table (shown in-game, like a real one), and sets them on the mortar. AI crews work it out.
