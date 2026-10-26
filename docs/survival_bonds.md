# Contractor: Fallen: bonds between people and gunsmithing (calls 74, 85)

Branch `claude/survival-bonds`. Two new files under scripts/survival/ (`Relationships`, `Gunsmith`) with small hooks in
the people, settlement, council, talk, journal, crafting, wear, RPG and build code. Every number is Proposed. Suite:
`bonds` (tests/bonds_test.gd).

## 1. Bonds (call 74): `Relationships`

- **The bond**: each pair's value -100..100 in their records' `relations` (the field the council, grief and nerve
  already read), kept symmetric (`Relationships.change`). Labels: stranger (never met, or under 5 either way),
  acquaintance, friend (30+), close friend (60+), rival (-25 or less), enemy (-60 or less), partner.
- **Drift, by the world hour** (never per frame): at home every pair of settlers awake gets 0.3 x (1 + traits that get
  on - traits that grate); the same shift (the same job worked this hour) +1.5 more; companions in the field drift the
  same way, +1 an hour with a horde about (danger shared). A companion's bond with the players creeps up 0.1 an hour.
- **Traits** (`FRICTION`, `AFFINITY`): the hot-headed grate on the calm and on each other, the kind on the cruel and the
  greedy, the hard worker on the lazy, the optimist on the gloomy, the pious on the cruel, the loyal on the fickle;
  shared calm, kind, optimist, pious, hard-working, loyal, brave, night owl, drinker or smoker traits get on.
- **Events** (one roll a pair an hour): an argument (0.05 a point of friction, +1 point a rival, +1 an enemy): -8 both,
  "argued" (-4, 12 h); a kind one comforts someone under mood 40 (0.04): +6, "comforted" (+5, 12 h); enemies brawl (0.1):
  -15, both hurt (6 trauma on a body, "bruises" on the record), "brawled" (-8, 2 days), and with two settlers the council
  asks whether to send the least liked away (`vote_out`: votes lean by each voter's bond with them; carried, they leave
  with a grudge). A life saved (down, then up again with someone within 3 m: `Relationships.watch_body`): +30 from the one
  saved, +10 back; a player who saved them gets +20 opinion.
- **Families** start at 70 (Children's `family`); a child minded ("minding" job) grows attached to that adult (+2 an hour,
  `carer`).
- **Partners**: two adults (18+) who are close friends both ways with no friction for 48 hours become a couple:
  "partnered" (+10, 3 days), "with_partner" (+4 while both live), one bunk between them (`Settlement.has_bed` /
  `free_beds`); a couple whose bond falls under 20 splits ("breakup", -10); a partner's death: "partner_died" (-30,
  10 days) and a nerve shake of 40 (by traits).
- **Rivals** won't work a shift together (the second refuses and takes their next job, or idles: an argument); in a vote
  the newer of two rivals in a faction votes alone (`Council.factions`).
- **The players' bond** (a person's opinion of that player): 60+ follows into worse odds (no refusal of a move into a
  horde) and talks you down with no cooldown; -30 or less refuses a risky order every time, loyal or not; -50 or less with
  a mood under 35 may leave (10% an hour).
- **The talk**: "Gift" (companions and settlers: an item stowed, +12 to the bond, +8 more for what they want) and
  "Settle it (a feud)": mediate their worst rival: chance 0.2 + 0.1 x social, social = 1 + 3 for the People person perk +
  2 for a teacher, nurse, police, paramedic or shop clerk background + up to 2 for what the two think of you; success lifts
  both to 10 ("made_peace"), failure costs 5; once a day a pair.
- **The People tab** (journal): a line a companion or settler: partner, friends, rivals, enemies (the strongest four) and
  "you: <label> (<n>)".

## 2. Gunsmithing (call 85): `Gunsmith`

- **Pieces** (appended at the end of `BuildPieces.PIECES` / `PIECE_KEYS`): `gun_bench` (Gunsmith bench: 4 planks, 2 scrap,
  1 machine parts, a wrench) and `gun_rack` (Armoury rack). The bench's menu (via `Infrastructure.piece_menu`): strip a
  broken gun, rebuild the broken gun, zero the sights, and "Make: ..." for every bench recipe.
- **Gates** (`Rpg.GATES`): `gunsmith_strip` firearms 7, `gunsmith` 8, `gunsmith_build` 9 (the suppressor stays 6, hand
  loads 7). The character screen names the tier.
- **Strip** (firearms 7, 20 s): a broken gun (slung, else stowed) becomes `gun_parts`: 1 a sidearm, 2 a long gun, 3 one
  over 4.5 kg. **Rebuild** (firearms 8, 60 s): the broken gun in a weapon slot from those parts and a weapon parts kit.
  **Zero** (firearms 7, 15 s): the gun's state carries the day (shown as "zeroed"; the aim effect is later).
- **Recipes** (data/survival_recipes.json, station `gun_bench`): spare parts (scrap + machine parts -> weapon parts kit,
  7), the oil-filter suppressor (oil filter + pipe, 6: wears out in 60 shots), hand-loads with a reloading press (9mm and
  5.56 twenty at a time, 12 ga buckshot ten; brass, primers, powder, lead; the rounds at hand-loaded condition 90), the
  pipe shotgun (7: single shot), the slam-fire shotgun (8: two shells), the crude SMG (9: 9mm on a pistol's magazine).
- **Quality**: a made or rebuilt gun starts at 55% at the work's own level, +15 a level over it (30-100), and comes empty.
- **Improvised guns** (tag `improvised`: the wear lane's x3 wear and jams): a misfire beyond jams, 0.02 + 0.3 x (wear
  fraction)^2 a shot, loses the round; a crude gun at 0% still fires, but 25% a shot it blows apart: the gun gone, powder
  burns on both forearms (Body's hands) and 12 trauma.
- **The gunsmith's order** (the settlement screen's order "gunsmith", count 1 on, 0 off): with a bench and an armoury rack
  built and a settler with firearms 7+ (their record's skills), at 06:00 (worked overnight) up to two worn or broken guns
  in the settlement's stock are brought to that smith's quality (a broken one needs firearms 8 and its gun parts from
  the stock).

## Left out

- Jealousy (only breakups), children born to couples, a couple's own bunk piece (they share a bed slot), grudges acted on
  beyond the vote, bonds between people of the world sim's groups, the brawl's animation (records and trauma only).
- No social skill line: "social" is computed (perk, background, standing) until the RPG lane adds one.
- Zeroing has no aim effect yet; converting sights (rails, mounts) is not built.
- Gun parts in the loot tables (found in gun shops, police stations, armouries) are not seeded yet; stripping is the
  source.
- Companions don't use the bench; the order works only guns in the stock, not those carried.
