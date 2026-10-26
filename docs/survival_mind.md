# Contractor: Fallen: the survivor's mind (calls 116-119, 130)

Branch `claude/survival-mind`. Everything lives in the body's Dictionary (`Survival.needs_of(s)`; a companion's is
the same dict as its record's `needs`), so it saves with the survivor and reaches the owner with `Survival.my_body`.
`Mind` (scripts/survival/mind.gd) is the glue: `Needs.server_step` calls `Mind.server_step` after the body's step,
`Needs.sway_mult` / `dulled` / `stamina_mult` read `Mind.sway_add` / `dulled_add` / `stamina_factor`,
`Survival.server_eat` calls `Mind.server_on_used`, `Needs.respawn` calls `Mind.reset`. Numbers are Proposed.

## 1. The nerve (call 116): `Nerve`

- `nerve` 0-100, a new survivor at 70. Shakes (`Nerve.SHAKE`): horde 18 (a horde in the zone, once per 12 world
  hours), bite 25, friend died 30 (a companion or settler: players in the zone, friends among companions; others 15),
  close call 10 (a bite dodged in melee), scream 8 (a screamer within 45 m), killed a person 15 (Harm's last hit: a
  player or companion), butchering 20, eating human meat 18. Traits: brave x0.7, calm x0.8, optimist x0.9, gloomy x1.1,
  timid / the coward flaw x1.3; the cruel x0.4 for killing and the dark line.
- Settles a world hour: asleep +5 (half after a nightmare), safe at the settlement with no dead within 40 m after an
  hour +4, otherwise a drift +0.5 back up to 60; awake with sleep under 30 it falls 1.5 an hour.
- "Talk me down" (a companion's talk menu): +25, then that companion is spent for 6 world hours; they get the
  `talked_down` moodlet (+3).
- Effects under 50 (`shake01`): aim sway +0.9, senses dulled 0.6 (ringing ears), stamina return x0.65 at the bottom.
- `Nerve.level(s)` 0 steady (60+), 1 uneasy, 2 shaken (under 35), 3 breaking (under 15): the tension layer's read.
  HUD signs "shaken" / "breaking" (level 2+). Companions hold the `shaken` (-6) and `nerve_broken` (-14) moodlets,
  and their mood drives the breaks as before.

## 2. Cannibalism (call 117): `Cannibalism`

- "Butcher for meat" on a dead survivor's body (in the More group; a knife or blade): 3 human meat
  (`human_meat`: 340 kcal, raw). Nerve and a `butchered` (-20, 10 days) moodlet for a companion; companions within
  25 m who aren't cruel get `saw_cannibalism` (-15) and think 30 less of the player.
- Eating it: nerve, `ate_human` (-25), the survivor record's `dark` list; the first time, a "dark" journal line and
  the world learns: `Intel.server_event(zone, "cannibalism")` and every group in the zone (not cultists) loses 25
  standing with the players.
- The wasting sickness: 20% a meal; hidden 10 world days, then tremors and fog growing, a memory line a day (told
  and journalled), death 21 days after it shows. Nothing cures it. Its own tick (`prion` in the body): the body's
  sickness table is a const.
- `Cannibalism.eats_the_dead(g)`: cultists, and a group with no food left. A flag for the world lane; nothing acts
  on it yet.

## 3. Addictions (call 118): `Addictions`

- Kinds: tobacco (line 30, withdrawal after 10 h), alcohol (35, 20 h), painkillers (35, 18 h), stimulants (30, 16 h).
  A dose: relief (nerve +10 / +15 / +6; stimulants sleep +15), habit + 6-10 times the item's mult, withdrawal gone.
- Items: `loose_cigarettes`, `spirits_flask`, `codeine`, `amphetamine` (stats `mind.habit`), and ibuprofen x0.3,
  caffeine pills x0.5, energy drinks x0.3, morphine x2 (through `Body.on_treated`).
- Withdrawal: w = 0.25 + (habit - line)/40; the habit falls 8 a day while it lasts (3 a day clean otherwise), so it
  eases over days and ends under the line. Effects: aim sway +0.5w, stamina x(1-0.25w), `Mind.work_mult` x(1-0.3w),
  nerve -2w an hour; the `withdrawal` moodlet (-10).
- The smoker and drinker flaws (and those traits on a person) start hooked at 55.
- Words: the body screen's summary, the readout's "Mind:" line, the character screen's "Nerve: ... Habits: ...".

## 4. Dreams, the journal's voice, letters (calls 119, 130)

- Dreams: every shake leaves a mark; on waking (`SurvivalSleep.wake` while asleep) the heaviest mark of the last 30
  world hours picks the dream (loss, dark, bite, killed, horde, hunger, kindness, else calm) from
  `survival_lines.json` "dreams"; the waker hears it with the wake line. A death in the last 3 days or breaking nerve
  makes the night a nightmare (`Dreams.on_sleep`): sleep's and the nerve's restore x0.5, -8 nerve on waking.
- The journal's voice: `Survival._journal_line` keeps `text` and adds `voice` (`JournalVoice.phrase(text,
  writer_traits())`): the event (death, bite, dark, break, arrival, letter, any) in the writer's voice trait from
  "journal.voices". Every new player survivor rolls one voice trait (`JournalVoice.roll_voice`); the hot-headed flaw
  lends its own. The journal screen shows the voice.
- Letters: "Write a letter" in the journal's People tab (`Intel.request_letter` -> `Letters.server_write`), kept on
  the survivor record; on death each lies on the body as a `letter` item (state: text, from, day, letter_id); any
  letter a player carries is read into the world's `letters_read` and listed in the People tab.

## Left out

- The story page (call 97) reads the `dark` list and the dark journal tags later.
- Groups that learn of cannibalism later by rumour don't lose standing (only those in the zone now).
- Companions don't dream or write letters; settlers' nerve steps hourly at home (`Mind.person_hour`).
- The new drug items are in no loot table yet; cooked human meat is not a recipe.
- Rubbing alcohol for surgery (`Surgery.server_drink`) isn't a drink dose.
