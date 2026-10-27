# Contractor: Fallen — people: companions, moods, dialogue, hiring, politics

How the living are people and not units: companions and settlers with needs, moods and
relations (calls 2, 18, 40), hiring by a want (call 2, S4), the contextual talk menu (call 54),
companions on mounts and at posts (call 35), co-op death and the newcomer (calls 13, 51), the
settlement's politics (calls 28, 59; the council's rules are in survival_building.md §7).
Written 2026-10-26. Inspired by RimWorld's colonists and the squad we already have.

## Where the build is (2026-10-26, branch claude/survival-people)

- **Phase B people built** (sections 1-6 and 8): `SurvivorPerson` (the one record in
  `Survival.state()["people"]`), `Moods` (the moodlet table, breaks by traits), `SurvivorsLayer`
  ("Survivors" on every survival zone: lone survivors placed by the seed, bodies in range, hiring,
  companions, favours, grief, graves, the rise, the take-over), `CompanionAI` (autonomy and refusals
  beside SquadAI), `TalkMenu` + `data/survival_lines.json` (the talk and lines by tag).
- Suite `fallenpeople` (tests/fallenpeople_test.gd): R2644 PASS (fallenpeople alone); R2645 FLAKY at f2aabb93 (fallenpeople passed; survival flaked once on the base melee check "a block held a while just blocks", passed the rerun).
- Proposed defaults (marked in code): 2-5 survivors a zone (+1 a village, up to 2), live within 90 m,
  money wants $200-1,500 paid in cash items (roll $50, bundle $250, brick $2,500, no change), break
  line 20 for 4 world hours then 25% an hour, rise after 180 s, burial 8 s with a shovel (etool) or
  25 s by hand, a body left out 4 pressure a day, newcomer loyalty 20, take-over at mood 40 and
  loyalty 40, refusal chance 0.95 - (loyalty + courage) / 250 (+0.1 under loyalty 30).
- Left for later: settlers and the settlement's jobs (the "settler" status exists, nothing sets it),
  captives, politics, romance and families, teaching, levelling (the RPG lane's skills are read
  through `Rpg.skills_of` when it exists), the barter screen (Trade is a line), a raider group (phase
  C), the take-over and newcomer screens (a message for now), a deserter's grudge acted on, roof
  spots, companions crossing zones with the squad (they come along to whatever zone is hosted),
  barricading doors, dressing for the weather, the "fetch" favour's item check beyond carrying it.

Built on: `Hiring.candidate` and `Roster` (names, roles, skills), `SquadAI` and the orders
(follow, move, hold, defend, assault, flank, regroup, fall back, release), `CivilianAI`,
`PersonLook`, the context menu (what you look at decides the first options), the TTS barks and
voice orders by callsign, `Vitals` and the medical system, `Consumables`.

## 1. A person

The one record for everyone (survival_world.md §4.2):

```
Person { id, name, age, sex, look, background, flaws, traits,
         skills: {line: xp}, level, perks,
         needs: {calories, water, sleep, warmth, hygiene, ...} (survival_medical.md),
         mood: 0..100, moodlets: [ {cause, value, until} ], break: null|kind,
         relations: {person_id: -100..100}, opinion_of_players: -100..100,
         wants: Want|null, loyalty, courage,
         kit, wounds, immune, history: [events] }
```

**Traits** (fixed at creation, a few per person): brave / timid, kind / cruel, loyal / fickle,
hard worker / lazy, optimist / gloomy, hot-headed / calm, pious, greedy, squeamish, a drinker,
a smoker, night owl. Traits bias moods, votes, the group kind they form and what they say.
Backgrounds and flaws (the RPG layer, survival_rpg.md) set the starting skills.

## 2. Needs, moods and breaks (call 40)

Every person has the same body as a player (survival_medical.md): hunger, thirst, sleep,
warmth, pain, sickness. On top, a **mood** from **moodlets**, each a cause with a value and a
duration, RimWorld-style, readable when you talk to them or on the settlement's people list:

| Moodlet (examples) | Value | Lasts |
|---|---|---|
| ate a hot meal / ate raw or rotten | +6 / -8 | a day |
| slept in a bed / on the ground / not at all | +4 / -4 / -12 | a day |
| warm and dry / cold / soaked | +2 / -6 / -8 | while it holds |
| a friend died / a friend is sick | -18 / -6 | 5 days / while |
| saw a horde / was bitten | -10 / -15 | 2 days / while on the clock |
| killed a person (not a raider in defence) | -8, less for the cruel | 3 days |
| a job they like / hate; too long a watch | +3 / -5; -6 | the day |
| a captive freed by us / a demand paid in people | +8 / -20 | 3 days / 10 days |
| the settlement grew / a wall fell / a raid repelled | +4 / -6 / +10 | 2 days |
| a grave for a friend / a body left out | +5 / -6 | 5 days |
| the player kept a promise / broke one | +6 / -10 | 5 days |

Mood under BREAK_LINE (Proposed 20) for a while rolls a **break** by traits: a crying fit
(useless for an hour), a rage (fights someone, breaks a piece), a binge (drinks the stock),
hiding (won't leave the bunk), **desertion** (leaves at night with some kit: a new lone
survivor in the world sim, with a grudge or not), **refusing an order** (the companion says
no and why; a second order within a minute is obeyed by the loyal and refused again by the
rest). High mood and loyalty give **courage** (holds under fire, carries a casualty, volunteers
for the night watch) and the "I'll stay" that keeps them through a bad season.

Moods feed the settlement: the council's votes (survival_building.md §7), the chance of theft
(someone steals food when hungry and gloomy), a split (a faction with low moods and a leader
trait leaves together).

## 3. Autonomy (call 40)

What a companion does **unasked**: eats and drinks from their kit and the stock, sleeps when
tired and safe, dresses for the weather if the kit is there, patches their own light wounds
(and asks for help with the rest), takes cover and fights back when attacked, calls out what
they see (the barks), loots a container within a few metres when the group is stopped and
quiet, picks up ammo for their gun and food, barricades a door at night when the group holds a
building, suggests plans ("we should move before dark", "that smoke is a camp", "I know a
clinic two towns over"), and refuses a bad order (into a horde, abandoning a friend) by
loyalty and courage.

What needs an **order or a job**: starting a fight, leaving the group, building, scavenging a
building, trading, taking a mount, handing over kit, guarding a spot (including a tied horse:
"stay with the horses" is a hold order on the mount), treating someone else.

Orders are the squad orders we have, plus survival's: hold here, watch (a post and a
direction), tend (a casualty, an animal, the fire), build this, carry that, go home (to the
settlement), split (a sub-team with its own lead), rest.

## 4. Hiring and recruiting (call 2, S4)

A survivor met in the world is a `Person` in a group of one (or a member of a group willing to
let them go). Talking shows who they are (name, background, skills by what you can read:
survival_rpg.md's diagnosis-like gate for skills too: a glance tells "handy", a day together
tells the level) and their **want**:
- **money** (cash, Proposed $200-1,500 by skill, more in a settlement that pays well);
- **an item** (from a want list: antibiotics, a rifle and mags, five tins, a backpack, warm
  boots, a book, their dog found);
- **a favour** (clear a building, bring something from a marked place, find someone, take
  them somewhere, avenge someone);
- **a place** (a bed in a settlement that has a doctor, a wall, a school for the kid).

Give it, or come back with it, and they join: a companion (in the 8-slot roster with the
players) or a **settler** (a job at the settlement, not in the roster). Trust starts low:
a new companion refuses dangerous orders more, shares less, and watches how you treat the
others. Some won't join at any price (a settler with a family stays; a cultist convert can't be
bought); some join and leave when their want is met and the mood is low.

**Captives**: a group can hold your people (a raid lost, a cultist capture); a captive is a
Person with a place; rescuing them is a goal you set (and your companions may set it
themselves: "we go get her"). You can hold captives too: a raider taken alive is a bargaining
chip with his group, a source of rumours, or a recruit if his mood turns.

## 5. Dialogue (call 54)

The contextual talk menu, generated from the Person and the moment:
- **Who** (name, background, a line in their voice: traits and mood colour the wording);
- **Want** (what would make them join, or what they're after now);
- **Ask** about a place (what they know by their history), a person, a group, the enclave,
  "what happened here" (the story trail, survival_world.md §7);
- **Trade** (the barter screen, survival_world.md §8);
- **Recruit** / **Give** / **Threaten** (a weapon up: the cowardly fold, the brave draw,
  everyone remembers);
- **Companions only**: how are you (needs and mood, in words), what do you think (their
  opinion of the plan, of a person, of the settlement), stay / come / tend, teach me (a skill
  lesson: survival_rpg.md).
Lines are written per group kind and mood in `data/survival_lines.json` and voiced by the TTS
barks; a line is picked by tags (kind, mood band, trait, season, relation), so it never runs
dry and never branches by script.

## 6. Companions in the field (call 35)

Riding: a companion takes a mount when there is one each; otherwise walks and keeps up (the
squad's follow). A tied horse with "stay with the horses" is a hold order on the mount: the
companion guards it, calms it (fieldcraft), and calls if something comes. Carts: a companion
drives a cart with the squad's driving (SquadDrivers). Casualties: the medical system's carry,
drag and treat, with the companion's medical skill gating what they can do
(survival_medical.md).

## 7. Levelling (call 18)

Companions and settlers earn XP in the lines they use (survival_rpg.md): a medic who treats
levels medical, a guard who fights levels firearms, a farmer levels farming. Their skills show
when you talk (by your read of them) and in the settlement's people list. A high-level
companion is worth more to the roster and to the groups that might lure them away (a settlement
with a better doctor's bed is a pull: the world sim's recruit goal works on your people too,
by their mood and loyalty).

## 8. Death, grief, graves (calls 13, 51)

A companion dies for good (no respawn). The body stays with its kit; the others get the grief
moodlet (bigger for friends), ask to **bury** them (a grave piece: the moodlet eases, the
journal records it; leaving a body out is its own moodlet and a pressure source). A player's
survivor who dies (permadeath): their companions grieve; the newcomer the player rolls is a
stranger to them (opinion from 0, trust low) until trust grows, or the player takes over a
willing companion (call 51: mood and loyalty allow it; the others see that person lead now).

## 9. Politics (calls 28, 59)

The council and leader challenge are in survival_building.md §7. People-side rules:
- **Factions** inside a settlement form from relations: a family, the old crew, the newcomers,
  the pious; a faction votes together and shares moodlets.
- **Standing**: the players' standing with the settlement is the sum of opinions, weighted by
  influence (the leader, the doctor, the oldest member count more).
- **Relations with other settlements**: alliance (trade, warnings, a shared defence call),
  feud (raids, refusals), protection (you guard them for a share).

## Holding or fleeing (call 143, branch claude/survival-flee)

The Captain (2026-10-26): "NPCs should flee if zombies are attacking their area/settlement and they don't have
weapons and have no guard etc. So the 3 person farmstead near my spawn should have seen all of its people leave since
they had no weapons." Built in `Holding` (scripts/survival/holding.gd); every number Proposed.

- **The judgement** (`Holding.judge`): a place's strength against its threat. Strength: an adult with a gun 1, melee
  only 0.5, unarmed 0.2, a child 0; a guard (an armed adult with `guard` set; at the settlement a guard on watch) +1; a
  world place's and group's defence x2; the settlement's defence builds 0.05 a point. Threat: 0.3 a head of the dead
  within 30 m of home or of one of them (15 m for one idling past; never one lying up in a nest), a horde's crowd heads
  the same. The threat outweighs them: the place breaks.
- **A household** (`Holding.household_key`): who lives together: a `household` id, else a family (Children's
  `family`), else a couple (Relationships' `partner`), else one alone. Children alone are Children's own running.
- **Live** (`Holding.server_tick`, every SurvivorsLayer tick): a broken household runs. The unarmed and anyone whose
  nerve breaks (nerve under 35 after the shake, courage under 25, timid) go at once; the armed cover the retreat 15 s
  and follow. They take food and water, shout ("They're coming over the fence! Run!"; the cover: "Go! I'll hold them
  here!") and run onto the nearest road (within 60 m, not toward the dead) and on to the nearest safe place they know
  that isn't toward the dead or overrun: another household's home (60 m+), a world group's camp, the players' farm, the
  edge of a village or town; else a crossing out of the zone (200 m worse than a place). The dead near them go after
  the slowest (the oldest, the hurt). Arrived (or after 150 s running, where they are) they live there as refugees
  (`refugee_from`); out of the zone they're lone survivors in the next one. Caught, they die or are bitten as before.
- **The place left** (`Holding.places()`, in the world section under "abandoned"): things dropped in the hurry (2-4 of
  tins, water, candles, matches) and a note ("They came over the fence and we couldn't hold it..."), the door open, a map
  mark ("Abandoned: the Halvorsens"), a journal line ("The Halvorsens left their farm to the dead.") and a world event
  ("abandoned") for the rumours. It's lootable; its people can reclaim it. Nothing is dropped inside the players' farm
  (its settlers would haul it off).
- **Live world camps** (WorldLive): a settlers' or scavengers' camp in the hosted zone judged by its bodies; broken,
  the group relocates (as in the sim) and its people run for the crossing toward where it goes.
- **The sim** (`Holding.sim_tick` from `WorldModel.step`, off the hosted zone and through the catch-up): the dead find a
  far household 0.2 times a day at full density (x(1 + pressure/50); +1.5 a day with a horde in the zone): a stray pack
  of 3, or a horde's heads up to 20. An unarmed household always runs (to another household's home 60 m+ off in the
  zone, else a place in the quietest neighbouring zone), the slowest caught 15% of the time (never a child); an armed
  one strong enough holds. A world group whose home a horde falls on runs instead of fighting it out when it can't
  hold (`WorldFights.horde_fight` -> `Holding.group_holds`: the fight's own sums; no guns and no ammo never holds): its
  home cleared and marked abandoned, 30% of its supplies left, goal "relocate" to the quietest neighbour, a new camp
  there. The zone loaded again (`Holding.server_zone_up`): the people the sim moved there grounded, the places left
  there get their signs and a journal line ("... The door stood open, things dropped in a hurry, a note.").
- **The players' settlement** (`Holding.settlement_tick`): the dead within its radius + 20 m: unarmed settlers hide 3 m
  behind a guard on shift or a player at home, else go to the shelter (a "shelter"/"safe_room" piece or a floor hatch,
  else the farmhouse), never past 80% of the radius; the armed stand. Can't hold: a journal line once ("Everyone to
  shelter!"). "Abandon the farm" (the settlement screen's council) puts it to a vote; carried, every settler runs as a
  refugee of the farm and comes back (a settler again) when it's clear.
- **Coming back** (`Holding.server_hour`, every world hour): a place clear of the dead (in the hosted zone: none within
  45 m, the players cleared it or they wandered off; elsewhere: no horde and the zone's pressure under 30) for 1.5 days
  gets its refugees back home ("The Halvorsens went back to their farm."). "It's clear now" (talk, on a refugee): true,
  they go now and think 12 better of you; not, "That's not what I saw."
- **Left out**: lone survivors' bodies are CivilianAI and never fight (holding means staying and hiding at home); the
  doors are open doorways in the buildings (no door to leave open); a refugee household joining the household it ran to;
  world groups taking refugees in as members; the players reclaiming an abandoned place as their own; a new "shelter"
  build piece (the hook reads one when the building lane adds it).

## 10. Performance

Moods tick per world hour per person, not per frame; the people list is read from the records.
Live companions are the squad we have (SquadAI); settlers at work are `CivilianAI` with a job
task; a settlement of 24 at work is within the fight case's AI budget with the dead's live
cap sharing it (survival_world.md §13).

## 11. Tests (phase B)

`people` suite (extending the existing one): a want met and the person joins; a want unmet
and they refuse; a hungry gloomy settler steals; a mood break rolls a desertion that creates a
lone survivor in the sim; a companion refuses an order into a horde and obeys a second from a
loyal one; a grave eases the grief moodlet; a captive rescued; the council vote weighted by
standing; a line picked by tags for a scared settler and a cocky raider; a tied horse guarded.

## 12. Calls answered (2026-10-26)

- **Relationships** (call 74): friendships, grudges and families as written, **plus romance
  and new families**: couples form over time (moodlets from a shared bunk, jealousy, a
  breakup), and in a long world **children** can be born, needing care for years of world time
  (a settlement job; a child is a Person with no jobs and big moodlets for everyone around).
- **Breaks** (call 75): the full set in §2, rare and trait-driven, as written.
- **Voice** (call 76): TTS lines by tags with subtitles until recorded; **the TTS model will be
  replaced by a bigger, better one** (more RAM is acceptable for this mode).
- **Death** (call 77): §8 as written, **and a companion killed by the dead rises** as a zombie
  in their kit (as a player does at collapse); putting them down is its own moodlet; burial or
  burning prevents it. A body nobody reaches in time is one more of the dead with a rifle.
