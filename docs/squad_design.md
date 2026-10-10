# Squad AI: design proposal (phase 3)

**Status:** decided 2026-10-09. Being built in the order below.
**Written:** 2026-10-09, after phase 2 (inventory depth) and downed/revive landed.

The roadmap calls this the make-or-break system. It's also where the codebase stops being
easy to change: navigation, the behaviour architecture, and how a shared squad works in
co-op will shape everything after it, including the phase 4 enemies. So it's written up
for review instead of built. Each decision below has a recommendation. Reply with the
numbers you agree with or want changed.

## What already exists that the squad can reuse

| System | How a squadmate uses it |
|---|---|
| `Player` host-side requests (`_server_fire`, `_server_reload`, `_server_use_medical`, `_server_revive`, `_server_interact`) | The AI drives a body through the same host-validated actions a player does, so squadmates follow the same rules (ammo, reload time, revive time). |
| `Inventory` with item state | Squadmates carry and use their own gear. Ammo, armor damage and kits all work unchanged. |
| `Vitals`: downed, bleed-out, `server_revive` | Squadmates can be revived by players, and players by squadmates. Bleeding out is where permadeath hooks in. |
| `CharacterModel` + `GearRig` | The same voxel soldiers with the same visible gear, hitboxes and armor. |
| `Ballistics`, `VoxelArmor`, voxel walls | Cover can be destroyed, so the AI must cope with cover disappearing. |
| Listen server, host authoritative | AI runs only on the host. Clients just see replicated bodies. |

## Decisions

All recommendations were accepted, plus the open question in 6:

| # | Decision |
|---|---|
| 1 | Shared `Soldier` body with `PlayerInput` and `SquadAI` drivers |
| 2 | Runtime navmesh, rebaked locally on breaches; computed cover points |
| 3 | Utility-scored intents with hysteresis; tuning in a data file |
| 4 | One lead player (host by default, any player can take lead); orders go to the whole squad |
| 5 | Squadmates loot for themselves; a carry allowance for players that grows with relationship (2 L to 10 L); loadouts persist |
| 6 | Permadeath on bleed-out. **Players who bleed out drop their backpack (with contents) where they fell** |
| 7 | Start with 2 squadmates |
| 8 | Phase 4 enemies use the same `Soldier` + AI stack |

## Proposal (as reviewed)

### 1. Body: a squadmate is a Player body without a human

**Recommendation:** split `Player` into a shared **`Soldier`** body (movement, the host-side
actions, gear, model) and two drivers:

- `PlayerInput`, the current input and camera code.
- `SquadAI`, a node that calls the same functions.

**Alternative:** a separate `Squadmate` scene that duplicates the parts it needs. It's
faster to start, but every rule (reload time, revive, carrying) then has to be kept in sync
in two places.

This is the biggest structural change, and the reason to stop here first.

### 2. Navigation

**Recommendation:** Godot's `NavigationRegion3D`, baked at runtime from the level's
collision, including the voxel walls.

- A bullet hole doesn't change paths. When a wall section loses enough voxels to become
  passable (a breach), rebake just that area, in the background.
- Cover points are computed, not hand-placed: sample points along the navmesh edges next
  to solid voxels, and score each one against known threats.

**Alternatives:**

- A coarse grid over the voxel world (e.g. 0.5 m cells). It's simple and reacts to
  destruction exactly, but you have to write pathfinding and smoothing yourself.
- Hand-placed waypoints. Fast, but they break as soon as walls are destroyed.

### 3. Behaviour architecture

**Recommendation:** utility scoring over a small set of **intents**, with a short state
machine inside each intent.

- **Intents:** Follow, Hold, Move to, Take cover, Engage, Revive (someone downed nearby),
  Heal self, Reload, Resupply (pick up ammo, meds or better armor for itself), Retreat.
- Every half second, each intent scores itself from 0 to 1 and the highest wins, with
  hysteresis so the squadmate doesn't flip between two close scores.
- Scores and thresholds live in a data file (like `items.json`), so tuning doesn't need code changes.
- It's easy to debug: a floating label shows the current intent and the top three scores.

**Alternatives:**

- Behaviour trees: more structure, but they need an editor or a lot of boilerplate in GDScript.
- One big state machine: quickest to start, but turns into spaghetti once there are 10 or more behaviours.

### 4. Who commands a shared squad in co-op

You chose one shared squad. Commands can come from any player.

**Recommendation:** the squad follows a **lead player**, the host by default. Any player
can take lead with a key. Orders (hold, move here, regroup) apply to the whole squad,
and the most recent order wins. Individual orders ("you, revive him") can come later.

**Alternative:** each squadmate follows its nearest player. That splits the squad naturally, but it's harder to read.

### 5. The squad inventory loop

You wanted squadmates who carry their own gear and aren't storage banks.

**Recommendation:**

- Squadmates **pick up for themselves**: their weapon's ammo, meds up to a target count,
  and a better armor tier if they find one. They never take objective items or salvage
  unless ordered to.
- **Carrying for a player** uses a separate allowance that grows with **relationship**
  (0–100), starting at 2 L and reaching 10 L at full trust.
  - Relationship rises with missions survived together and revives.
  - It falls when you leave them downed or take their gear.
  - Giving them an item uses the existing inventory screen, with a new "Give to" target.
- **Loadouts persist** between missions, along with damage, as item state.

### 6. Permadeath

You chose revivable, with permadeath if they bleed out or are left behind at extraction.

**Recommendation:**

- Bleeding out uses the existing 60 s timer. When it runs out, the squadmate is removed from the roster for good and their gear drops where they fell (lootable).
- "Left at extraction" waits for phase 4 (extraction doesn't exist yet). The rule would be: anyone not inside the extraction zone when it departs is gone.
- **Open question:** should *players* who bleed out lose anything? Today they just respawn
  with full gear. Options: drop the backpack at the death spot, lose what's carried in
  hands, or nothing.

### 7. Squad size and stats

You chose a shared squad. **Recommendation:** start with **2 squadmates**, each with:

- `combat` (0–1): aim error and how fast they react.
- `discipline` (0–1): how well they hold orders under fire and keep their spacing.
- `experience`: grows with missions survived and slowly raises the other two.
- `relationship`: per squadmate, shared by the whole player team.

Aim error comes from the same spread cone players use, widened by `(1 - combat)`, so AI
doesn't need its own weapon rules.

### 8. Enemies

Phase 4 enemies should use the same `Soldier` body and `SquadAI` with a hostile faction
and different intent weights. **Recommendation:** decide this now, even though enemies
come later, because it's the main payoff of decision 1.

## Proposed build order (once decided)

1. ~~Split `Player` into `Soldier`, `PlayerInput` and the AI driver. Pure refactor, verified by the existing three test suites.~~ Done: `scripts/soldier/soldier.gd`, `scripts/player/player_input.gd`, `scenes/soldier.tscn` (base) and `scenes/player.tscn` (inherits it, adds the camera and the driver). Bodies named `AI...` are host-owned.
2. Runtime navmesh over the compound, with rebakes on breaches. Debug drawing.
3. A squadmate that follows, holds and moves to a point, with commands on hotkeys.
4. Cover sampling, plus Take cover and Engage against the target dummies, later moving ones.
5. Revive, Heal self, Reload and Resupply, including reviving players.
6. Relationship, carry allowance and permadeath, with the roster saved.
7. Tests for each step: headless scenarios like "squadmate revives a downed player within N seconds".

## Risks

| Risk | Mitigation |
|---|---|
| Navmesh rebakes are too slow after voxel destruction | Rebake only the changed tiles, in the background; until it finishes the AI treats the breach as blocked |
| AI looks dumb in cover against destructible walls | Re-score cover when a cover voxel volume loses more than X% of its voxels; prefer the thickest cover |
| Host CPU with 2–3 squadmates plus about 15 enemies | Intents re-score at 2 Hz; perception raycasts are budgeted per frame |
| Co-op command conflicts | One lead player, the most recent order wins, and the HUD shows who leads |
