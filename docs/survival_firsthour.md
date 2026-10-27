# Contractor: Fallen, the first hour

After the Captain's first playtest ("def needs more work before playtesting": not fun yet, he didn't
know the basic controls and had to ask how to melee; "at the spawn there is nothing"; "the zombies
come too frequently out in the wild"; "nearly non existent out in the wild and near AI farms"; "guns
shouldn't pull zombies constantly out in desolate zones"). A huge sandbox with no direction loses a
player in the first hour, so the first hour gets direction, pacing and teaching, without a
hand-holding tutorial. Code: `scripts/survival/first_hour.gd` (FirstHour), `field_hints.gd`
(FieldHints); suite `firsthour`. **Every number here is Proposed.**

## 1. The start farmstead

A new world used to put the survivor at a bare edge point of the start zone (ZoneDef.generate's
insertion: 350 m clear of every site), and the cold open's "farm" was a fiction there. Now the start
zone's def gets a farm landmark site (`BuildingGen.site("farm")`: an enterable farmhouse, a barn,
silos, a fenced pen with a trough and field shelter, hay, a stone well in the yard) 70 m + its half
size in from the first insertion point, clear of the zone's sites by 160 m, and the insertion moves
to the farmhouse's front door, outside (`FirstHour.farmstead`, applied in `Survival._host_zone` to
the start zone, the same every time from the world seed). Three boxes are rolled once (a pantry
shelf and a dresser in the house, a tool chest in the barn: food, water, cloth, bandages, planks,
ties; the first roll thinned by FoundLoot, so they feel picked at but aren't empty; no guns). The
barn holds the thread's melee weapon; planks and a hammer lie by the stove. Left out: a vehicle
wreck to strip at the farm (the cold open's "wreck on the road" roll is still the only one) and a
ploughed field of its own (the terrain's fields are where they fall).

Measured headless (`firsthour`, the survey prints everything within 120 m): see section 6.

## 2. The first-day thread

The note on the table ends with a postscript; the journal says "Three things before dark". Each goal
is a journal line and a map mark (kind "goal"), completes by doing it and pays a little:

| Goal | Done when | Pays |
|---|---|---|
| Water | Drink or Fill a bottle at the well (the contextual menu on the well, any well/trough prop, or any river/lake) | fieldcraft 30 XP, nerve +8, 2 purification tablets |
| A better weapon | Any non-knife melee weapon carried (the barn's crowbar/machete/hatchet, or the note's gift) | melee 30 XP, nerve +8, a whetstone |
| Shelter | A shutter, door, gate, hatch or fence built within 20 m of the farmhouse, or 2 blocks | building 40 XP, nerve +10, a tin |
| The voice (day 2, from 09:00) | The lone survivor the farm's old set picked up (want: a bed with walls), placed by a landmark 150-450 m out and marked, recruited | fieldcraft 20 XP, nerve +12 |

Nothing forces the order; ignoring it costs nothing. Water is new on the contextual menu: **Drink**
and **Fill a bottle** on any water (Fieldwork.server_water: raw water's sickness roll by its quality;
the farm's well is dirty while the cold open's "well gone bad" holds; the sea refuses).

## 3. Control hints, once each

The host sees the situation (FirstHour.situation) and tells the owner once a session; the owner
shows it once per profile (`user://fallen_hints.cfg` under the profile key) with his own bindings
(FieldHints.key_name reads the InputMap: "Ctrl", "6", "Click", "Right-click"), for 9 s under the
compass. The Accessibility tab's **Hints** turns them off. The journal's **Field notes** tab lists
every hint seen, to reread.

| Hint | When |
|---|---|
| Silent kill ({interact} behind it with a blade) | one of the dead within 15 m, unaware |
| Melee (swing, hold heavy, block, parry, dodge) | a melee weapon up |
| Night (Wait until dawn from the ground's menu) | the first dusk |
| Boxes (search; picked-over look open) | a box within 3 m |
| Loading magazines (inventory, right-click the rounds) | loose rounds and a magazine of their calibre |
| Injuries (body screen, medical menu) | the first wound that wants care |
| Companions (talk, order) | the first companion |
| Building (6 build mode and its keys) | building materials carried |
| Food and water | hunger or thirst under 40 |

## 4. Pacing the first night

Below "dead: High": no horde forms (the pressure's, a siege, one walking in from the world sim) until
day 2's 06:00; the dead's night pace bonus (ZombieAI.NIGHT_WALK_MULT) is off on night 1, half on
night 2, whole from night 3. High keeps the hard first night. The cold open's small first-night
pressure (25, under the drift) is kept.

## 5. What now

The journal's Log page opens with **Now**: the open goals with the real keys and the nearest landmark
not yet visited ("Nearest place not yet seen: the water tower, 420 m north"). A landmark is visited
within 35 m (the map section's "visited", sent to every peer); the map draws unvisited ones as "?".

## 6. The dead's density

The rule (the Captain): the open country holds almost none of the dead; places the living hold are
quiet; the dead concentrate in towns, villages, nests and sites; a shot draws the dead that are
there, not a stream from forever away.

- **Open country** (no site under him): 1 of the dead kept about a survivor (was 2; 2 again from day 7
  or two zones out), and a new one at most every 150 simulated seconds over the open pace (0.5 on
  days 1-2, 0.75 on days 3-6, 1 from 7; +0.25 a zone tier; times the "dead" option): one every ~5
  minutes of walking on day 1, every ~2.5 from day 7. A cap of 2 new a 64 m area a world hour.
- **The start farmstead**: 1 about him, at the open country's spacing.
- **Quiet places**: within 150 m of a lone survivor's home or a living world group's home or held
  place in the zone, none come about a survivor, the crowd isn't seeded, and the crowd's idle drift
  turns away from it (sieges, hordes and noise still bring them).
- **Sites** (towns, villages, compounds...): unchanged (DEAD_NEAR, a new one each 2 s tick).
- **Noise**: a noise's pressure is scaled by what it can draw on: 1 by a town or city (or a nest)
  within 300 m, 0.8 a village, 0.5-0.6 military sites, 0.3 a farm, 0.08 the open, 0 a quiet place.
  A loud noise pulls the crowd heads within its heard radius + 50 m straight at it; the crowd drifts
  toward the pressure point only from within 300 m. A horde forms only with a town, city, village or
  nest within 400 m of the point.

Before/after, measured headless by the `firsthour` suite (simulated time: `_populate` every 2 s, the
crowd stepped; `Survival.legacy_spawns` runs the old rules for "before"):

RESULTS_PLACEHOLDER

## 7. Left out

A vehicle wreck at the farm; a field of its own; roads as a place the dead gather (the open-country
rule treats a road like the open); "where people died" as a pull on the dead beyond the bodies
that rise; hordes from towns and nests on their own clock (they still come from sustained noise in
or by a town); "days survived" is the world's day, not this survivor's.
