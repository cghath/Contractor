# Contractor: Fallen: children, faith and legacy (calls 128-130)

Branch `claude/survival-children`. Three new files under scripts/survival/ (`Children`, `Faith`, `Legacy`) with small
hooks in the people, settlement, council, talk, journal and build code. Every number is Proposed. Suite: `children`.

## 1. Children (call 128): `Children`

- **Who**: a SurvivorPerson record with `child: true` and `age` 5-15 (`Children.opts_for`). Lone survivors placed in a
  zone (`SurvivorsLayer.server_place_zone`) have families: 30% of them have a child beside them (`family` / `guardian`),
  and 35% of zones have an orphan 30-60 m from someone (`orphan: true`). The world's groups roll children once
  (`Children.server_roll_world` from `Survival._world_level_ready`): settlers 60%, cultists 30%, scavengers 10%, 1-2
  each, never the leader. Their own rng throughout, so the adults' rolls don't change.
- **The body**: the model at x0.7 and the capsule by `Children.size_of` (SoldierMovement's size); meta `child` on every
  peer (the known info carries `child`/`orphan`). `Vitals.shielded`: nothing hurts them on screen.
- **They can't fight**: weapons are stripped off their body, a weapon given is refused ("I don't want that."), no
  Recruit / Threaten / Trade / Take along in the talk, never a companion, no guard job, no council vote.
- **The dead**: `ZombieAI._spot` and `_smell` skip a child. Each SurvivorsLayer tick (`Children.server_tick`): the dead
  within 14 m send a child running to the nearest adult within 30 m (a player or a living adult's body), else to the
  nearest building, and the companions and settlers take "child_saw"; with no adult within 30 m one of the dead within
  2 m takes them: the body goes, status `taken`, a journal line ("X was taken. We never found him."), `child_taken`
  (-25, ten days) and a nerve shake for every companion and settler. Never a body.
- **The player**: `Harm.note_hit` and `Melee._hit` ignore a hit on a child and tell a player "You don't.".
- **Orphans**: "Come with me" on a lone child (TalkMenu): they settle at the settlement (a settler, not a companion).
  A family's child settles when their adult is recruited or settles (`server_family_follows`).
- **Care** (`Children.settlement_hour`, checked at 20:00): each child needs two adult hours a day (the "minding" job,
  `Children.mind`) and food from the stores like anyone; a hungry child (hunger under 35) gives every adult settler
  "child_hungry" (-8, a day); fed and minded, "child_safe" (+4, held). Light jobs from 12: "forage" (wild berries and
  apples, 0.4/h), "minding", "water" (a bottle of dirty water every two hours).
- **Votes** (`Council`): children are left out of the factions. With children at home: a demand's pay +1.5, a raid's
  stay +1.5, a question with `risky: true` +1.5 against; a raid or risky question needs two thirds of the weight
  (`Children.risky_result`); a hungry child adds +4 against taking more in.
- **A reason to settle**: `WorldGoals.options` drops "raid" and "hunt_player" for a group with children and adds
  +0.35 to "settle" and "defend"; children add nothing to a group's fight strength.

## 2. Faith and funerals (call 129): `Faith`

No real religion is named: a plain faith, a cross or a bare altar, words over the dead.

- **The rite**: burying a known survivor (`SurvivorsLayer.server_bury`) opens a rite when a pious companion (first) or
  settler is in the zone: they ask for words ("rite_ask"). "Say a few words" on them (the squadmate menu, or the
  settler's) within 12 m of the grave: "words_said" (+6, three days) for everyone within 25 m and the pious, the
  speaker's nerve +12. "Not now", or six hours unanswered: the pious takes "no_words" (-8, two days).
- **The chapel**: build pieces `chapel_bench` and `altar` (planks and a candle); the settlement has a chapel where an
  altar stands (`Settlement.refresh` counts `altars`). A pious settler gets the "service" job first; one service a
  day: "service" (+5) for every member, the settlement's `faith` +6 (it fades 1 a day without one), and the council
  leans to charity (take in +faith/50) and against raids.
- **Small rites**: grace at a meal hour when a pious settler cooks ("grace" +2); a prayer before a raid the council
  sends (`Faith.server_prayer`, "prayer" +3); a vigil the night after a companion or settler dies (22:00,
  `Faith.server_vigil`): everyone loses 20 sleep and the loss moodlets for the dead are halved ("vigil" +2).
- **Cultists, the dark mirror**: each cultist camp in the hosted zone holds a rite at midnight (+8 pressure where it
  is); a cult's standing with the players can't rise (`WorldGroup.change_relation` refuses it: `Faith.standing_locked`).
  A cultist deserter (`Faith.server_add_deserter`; `cult_deserter`) asks to be cleansed; settled, three services
  cleanse them (`cleansed`, the pious trait, "cleansed" +8).

## 3. Letters and legacy (call 130): `Legacy`

- **The lineage** (`Survival.state()["lineage"]`): `Legacy.server_on_death` (from `Survival.server_player_died`, before
  the newcomer) writes every player survivor down: name, generation, background (the RPG one), born and died day, days
  lived, cause ("killed by the dead", "shot", "caught in a blast", "a fall", else the wound model's), the dead put down
  and the things built (the world's `kills` / `built_n` against `kills0` / `built0` on the survivor at birth:
  `Legacy.on_born`, `Legacy.note_built` from Builder), the letters, the companions and settlers who outlived them.
- **Last words**: with no letter, the journal writes them in the survivor's voice (`Legacy.LAST_WORDS` by trait).
- **The journal**: a "Lineage" tab (`JournalScreen.view().lineage`: everyone in order, then the one alive); the People
  tab has every dead one's letters "A letter found on <name>..." in their voice (`Legacy.found_lines`), as well as the
  letter items read (Letters).
- **Graves**: a burial places a `grave_marker` piece (inscribed: the piece's `text`) and a map mark of kind "grave"
  (never fades); a player survivor's death place is marked on the map too. The scars page (call 97) is to read
  `Legacy.lineage()` when it's built.

## Left out (later)

- Children born in a long world and growing up (call 74's families); a child companion's voice clips (lines are in
  data/survival_lines.json with `age: young`, none rendered).
- The chapel's look (the altar is a plain block piece); a cross vs. bare altar choice.
- Raiders choosing targets: they never hit a child because the body is shielded, not because the AI skips them.
- Per-player kill counts in co-op (the lineage counts the world's kills while the survivor lived).
