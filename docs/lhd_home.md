# The LHD as home, and taking a zone for the FOB

Captain, 2026-10-20: "we need the lhd functional as thats the players home until they finally take
a zone to be their FOB". This doc covers the walkable LHD, how home switches, and the take-a-zone
story. **Captain** marks his calls; **Proposed** marks mine, for him to confirm or change.

Code: `scripts/campaign/lhd_level.gd` (the level), `scripts/campaign/lhd_layout.gd` (its voxels and
positions), `scripts/campaign/lhd_nav.gd` (its navmesh), `scripts/campaign/zone_control.gd` (zone
control, home, the story), `scenes/levels/lhd.tscn`. Tests: `tests/lhd_home_test.gd`.

## 1. The ship

**Captain:** a walkable ship. You spawn aboard. The flight deck has helicopters and you deploy from
it; the hangar deck holds the armory and stash, the muster line and the vehicle park; there are
medbay, hiring and ops desk rooms with the same terminals the FOB has.

**Proposed layout** (ship metres: origin at the middle of the hangar floor, bow -z, starboard +x):

| Part | Where | Notes |
| --- | --- | --- |
| Hull | 32 m beam, 160 m flight deck | Shorter than the 257 m offshore art: the whole ship has to sit inside one voxel world a player's viewer loads. The offshore LHD (`LhdArt`) is unchanged. |
| Hangar deck | floor at 0, 96 m long, 6.6 m clear | The flat "ground" of the level. The waterline is 11 m below it and the flight deck 7 m above, so the flight deck stands 18 m over the water, as offshore. |
| Armory | port side, forward | The stash lies on its floor as at the FOB (BaseArmory slots); overflow racks run aft along the port side. Shop terminal and delivery counter by its door, supply cage beside. |
| Medbay | starboard, forward | Medbay desk inside. |
| Hiring office | starboard, aft of the medbay | Hiring board inside. |
| Muster line | hangar centre, athwartships | The available roster stands in their gear, 9 a row, as at the FOB. |
| Vehicle park | hangar aft | Motor pool desk, painted bays, the pool's vehicles parked as props (up to 6). |
| Stairs | starboard amidships (climbing forward), port aft (climbing aft) | 35 steps of 0.2 m, the house stair (BuildingGen sizes), railed stairwells on the flight deck. |
| Flight deck | 7 m up | Two UH-60s and an AH-1Z parked on painted spots on the port side; railings round the edge. |
| Island | starboard, forward of the stair | The ops room is in it, on the flight deck: the ops desk (squad, roster, deploy) beside the helicopters. |

Players spawn in the hangar, aft of the muster line. Squadmates have a navmesh on both decks and the
stairs. Nothing is hostile aboard and the ship is never attacked (Captain, wave 5b). Defences, guards
and assaults belong to a FOB ashore, so the ops desk refuses defences while home is the LHD.

**Deploying (Proposed):** unchanged in mechanics. The ops desk's Deploy takes the squad into the
contract's zone, where the briefing's insertion flies them in (the helicopter from the LHD on a
coastal zone, `Lhd.install`). The ops room sits on the flight deck so the squad walks up to the
helicopters to deploy; the parked helicopters are props.

## 2. Campaign start and home

- **Proposed:** a new campaign starts aboard the LHD (`zone_control.home` = `"lhd"`). Under the test
  scenes the old base stays the default, as `base_zone_mode` already does; `BaseHub.lhd_home_mode`
  forces it either way.
- **Proposed, existing saves:** a campaign saved before this (no `zone_control` section) keeps its
  FOB: its home reads as `"fob"` and nothing about it changes. It doesn't get the charter story.
- Home is campaign state in the `zone_control` section: `home` (`"lhd"` or `"fob"`) and `fob_zone`
  (the zone the FOB was built in; `""` for an old save's inland FOB). `BaseHub.base_info()` reads it:
  the LHD level, or the base zone.
- **Proposed, region map:** while home is the LHD there is no base cell on the region map (no zone
  has a crossing "To FOB": you can't walk to a ship). Once a zone becomes the FOB, the base takes
  that zone's cell, and its neighbours' crossings lead home.

## 3. Taking a zone

**Captain:** mix knocking out a zone's HQ and QRF bases with a seize-and-hold contract, "with a
little bit of story":

1. **Control flips.** A zone's control flips to the company once every HQ and QRF base in it has
   been taken out (`ZoneLevel.site_down`). **Proposed:** progress counts across deployments: a site
   taken out once stays counted, so one long hot-zone run or several shorter ones both work.
   Only zones with an HQ or a QRF base can flip (today, the hot zones). Saved in the campaign.
2. **The liaison's call** (story). The moment it flips, the client's liaison comes up on the radio:
   good work, their command there is broken; the LHD's charter is running out and the client wants
   the company ashore; take and hold a site there and it's yours for a FOB.
3. **The seize-and-hold contract** goes on the board for that zone: take the zone's HQ (whatever is
   left in it) and hold it through the counterattack (the Hold the line objective: waves from 3-4
   directions for 7-10 minutes). **Proposed:** pays as a hot-zone Hold the line; if it fails or
   lapses, the liaison puts it back on the board the next day. No deadline on the charter: the
   charter running out is story, not a fail state.
4. **The win moves home.** Completing it makes that zone the FOB: the base zone (BaseZoneLevel, the
   FOB as before with its terminals, stash, muster line, helipad, vehicle park and range) built on
   that zone's ground (its seed and terrain) with the FOB at its centre, and the squad comes home to
   it after the debrief. **Proposed:** no extra charge for the move (the contract's days cover it),
   and the stash, roster and motor pool simply move with the company.

Another zone flipping after the move counts on the map, but there's no second FOB and no moving it
yet (follow-up).

## 4. Co-op and late joiners

Nothing new: the LHD is a level like the FOB (`level_info` `{"level": "lhd"}`), so joining clients
load it through LevelSwitch's handshake, and a late joiner joins aboard. The stash, muster line and
terminals are the FOB's own code (BaseFob with the ship's layout), so they replicate the same way.
Clients read home and zone control from the base screen's view (`view.zone_control`).

## 5. After the FOB

The LHD stays offshore on coastal zones as the support origin (`Lhd.install`: helicopters from its
deck, AAVs from its stern), as now. Home is the FOB; the LHD level isn't loaded again.

## Follow-ups

- The FOB's zone still appears as a contract zone on the board (ContractGen picks it); it should
  drop out once it's the FOB.
- The world map should show zone control (`ZoneControl.control(zone_id)`) and the LHD offshore.
- Moving the FOB again, or a second FOB, and the LHD upgrades over time (design doc).
