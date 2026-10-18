# AI competence: what others do, what we have, what's next (2026-10-18)

The Captain: "look at some various media and see if theres anything about our ai we can improve so
theyre competent", and "check out the module thats included in sog prarie fire ... about hunting
players". What the sources say, how our AI compares, and what to do next. We learn from these games
and mods; we don't copy them.

## Sources and what they teach

| Source | The lesson |
|---|---|
| F.E.A.R. (Jeff Orkin, GDC 2006, "Three States and a Plan") | A small state machine plus a planner. Much of the "smart squad" is the enemy *saying* what it's doing ("Flanking!", "Cover me!") and level cover placed to the player's side: players credit what they can hear and see. |
| Killzone (Guerrilla, GDC Europe 2005, "Dynamic Procedural Tactics") | Positions scored by a weighted sum: proximity, line of fire to the main threat (more with partial cover), cover from the other threats, preferred fighting range. Tactical pathfinding: A* link costs raised for crossing friendly lines of fire and for being under fire. Suppression aimed at the positions the threat could use to attack, not into the wall it hides behind. |
| AiGameDev, GDC 2012, "Believable Tactics for Squad AI" | Attacking and flanking, suppression, leading and following the player; centralized versus distributed squad control. |
| LAMBS Danger (Arma 3) | Buildings are part of the fight: AI clears them methodically, garrisons and hides in them; suppression of suspected positions with a friendly-fire check; group tactics that can be cancelled. |
| VCOM AI (Arma 3) | Reinforcements called in proportion to the threat, with a cooldown per region; cover-to-cover moves; static weapons, artillery, mines. |
| S.O.G. Prairie Fire, Tracker module (community descriptions; no official write-up found) | Trackers spawn near the team, find its trail, fire signal shots to bring friendly units, then follow and harass until dealt with. Counterplay: mines on your six, dog-legs to throw them off, suppressed weapons. A companion requester sends two fire teams to the approximate position each time a group spots the team. |
| Gray Zone Warfare player reports; an Arma Reforger perception mod | The commonest complaint about "hard" AI is a hive mind with a sixth sense: instant, exact position sharing. The fix modders use: delayed reports with position error, gunshots as a search area, shorter memory. |
| Splinter Cell: Blacklist (Martin Walsh, GDC 2014) | Plausible beats smart: fairness, consistency and intelligence pull against each other. |

## Where we stand

Already there: fire and maneuver with flank lanes and a base of fire, bounding, building clearing
and garrisons, suppression that wanders round a position, a friendly-in-line check before firing,
a last known position whose uncertainty grows, an enemy high command with fog and reserves, morale,
casualty care, enemy callouts in their own language (heard, not subtitled).

Done today (branch `claude/open-items-oct18`):

- **One contact, one coordinated response.** Patrol looks merge per contact and grow slowly; hot
  zones' QRF waves and hunter teams on one contact form one push. With two or more groups, each
  waits at its own hidden rally point and all go in together: a pincer at one moment instead of a
  trickle from every side.
- **Trackers** (`SquadTrail`, `EnemyResponse._track`): the squad leaves a trail; hunters and patrols
  out looking pick it up, fire signal shots (a patrol comes), and follow it mark by mark, pausing at
  hard turns. Roads and water break the trail. Dog-legs work against them, as they should.

## Next, in order (proposed)

1. **Honest information sharing.** Contact reports between squads and over the net arrive after a
   short delay with position error that shrinks with the reporter's distance and optics. The zone
   knows where you were, roughly, a few seconds ago, not where you are. Fixes the "sixth sense".
2. **Tactical movement under fire** (Killzone). When a threat is known, a squad's route between
   points prefers ground out of the threat's line of fire: score candidate legs by exposure and pick
   cover-to-cover hops instead of the straight path.
3. **Suppress where they'll come up** (Killzone). A base of fire aims bursts at the positions the
   squad could fire from (the corners, the window, the ridge line next to the last known spot), not
   only around the spot itself.
4. **Hear the enemy's intent.** Their lines are voiced but never subtitled; an optional
   "interpreter" setting (or a squadmate who speaks the language) would subtitle the tactical ones
   ("they're flanking left"), which is how players read AI as smart.
5. **Reinforcement requests from spotters** (VCOM, SOG). A group that spots the squad asks for
   help on the net, paid from the reserves (hot zones: EnemyCommand already decides), at most so
   often per area.
6. **Mines and traps on the trail** for the players: a claymore or tripwire behind you is the real
   answer to trackers; the AI should find and avoid them some of the time.

## Sources

- [GDC 2006: Three States and a Plan, the AI of F.E.A.R. (PDF)](https://pages.cs.wisc.edu/~dyer/cs540/handouts/gdc2006_orkin_jeff_fear.pdf)
- [Killzone's AI: Dynamic Procedural Tactics (Guerrilla, PDF)](https://www.guerrilla-games.com/media/News/Files/gdce05_killzone_ai.pdf)
- [GDC Vault: Believable Tactics for Squad AI](https://gdcvault.com/play/1015665/Believable-Tactics-for-Squad)
- [LAMBS Danger.fsm changelog](https://steamcommunity.com/sharedfiles/filedetails/changelog/1858075458?p=1)
- [VCOM AI changelog](https://steamcommunity.com/sharedfiles/filedetails/changelog/721359761?p=2)
- [SOG Prairie Fire community: Question about trackers](https://community.sogpf.com/threads/230-Question-about-trackers)
- [SOG Prairie Fire: Trail Watchers comments (trackers in play)](https://steamcommunity.com/sharedfiles/filedetails/comments/2635843222)
- [Real and Simulated Wars: SOG Prairie Fire patrol tactics](https://kriegsimulation.blogspot.com/2021/06/arma-3-creator-dlc-sog-prairie-fire.html)
- [Arma Reforger: AI Perception Rebalance](https://reforger.armaplatform.com/workshop/6A3AAAF98E81E458-AIPerceptionRebalance)
- [Bringing balance to stealth AI in Splinter Cell: Blacklist](https://gamedeveloper.com/design/bringing-balance-to-stealth-ai-in-splinter-cell-blacklist)
- [Gray Zone Warfare Steam discussion (AI complaints)](https://steamcommunity.com/app/2479810/discussions/0/4342111082246108477)
