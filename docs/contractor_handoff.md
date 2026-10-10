# Contractor Handoff

Oct 10, 2026 · @Captain

## What this is

Contractor is a near-future tactical FPS. You play a contractor who commands an 8-slot squad (up to 4 players, AI fills the rest) through a persistent, MechWarrior 5-style campaign. It features physical inventory, an ACE3 and KAT-style wound model instead of hitpoints, and squad AI modeled on LAMBS Danger and VCOM. The shooter and the campaign matter equally.

This handoff sums up every decision Captain made up to 2026-10-10, for the people building it. The design doc stays the full reference; when the two disagree, the design doc wins.

| What | Where |
| --- | --- |
| Design doc (full detail, tables, numbers) | [Contractor Design Doc](https://claude.ai/code/artifact/3eab3511-5dff-41c4-bdf4-105652604561) |
| Code | [github.com/cghath/Contractor](https://github.com/cghath/Contractor), local copy at `B:\Contractor` on Captain's desktop |
| Medical and AI research | [Arma mod research doc](https://claude.ai/code/artifact/837553d8-88f9-4d66-894b-b409aca402d7) |
| Original brief | Handoff Persistent-Campaign Tactical FPS with Physical Inventory.docx, in the project files |

**Stack:** Godot 4.7.2 with standard Voxel Tools 1.7 (Captain), GDScript, Jolt physics, and an ENet listen server that is host-authoritative for up to 4 players.

**Team:** Captain and Claude, plus a teammate and their Claude.

**Where the build is:** Foundation (phase 1) is done and Inventory depth (phase 2) is done but unreleased. Squad prototype (phase 3) is next. The local `phase3-squad` branch already has throwables, 8-slot squad scaling, battle buddies and casualty care, committed locally but not pushed. Health in code is still HP-based.

## Working agreements

- Nothing is pushed to the repo without Captain's say-so.
- Captain does the playtesting. Claude runs only quick smoke checks, never long test runs.
- After each chunk of work, leave a playable test build in a dated folder under the repo.
- When Captain says "pause", "halt" or "don't start on anything else yet", stop and wait.
- When Captain is going back and forth in a thread, reply as each change lands, rather than silently editing earlier messages.
- A Captain decision overrides the README's locked decisions and `docs/squad_design.md`. Update those files to match when the code changes.

## Code changes the decisions require

Phase 3 (Squad prototype) is the next build step and carries most of these changes, because squadmates have to treat each other with the new wound model. Tick items off as they land.

**Phase 3: Squad prototype**

- [ ] Replace HP in `Vitals` with the blood and wound model: 6 L of blood, wounds per body part, pain, unconsciousness and cardiac arrest with a 10-minute window.
- [ ] Turn the IFAK and trauma kit into the real kit items. Keep `_server_use_medical` so every treatment uses a real item.
- [ ] Make permadeath on bleed-out and MIA when left behind alive apply to AI squadmates only.
- [ ] Change player death: respawn in the default kit and leave the dead player's gear in the world with a map marker. Today players respawn at the gate with full gear.
- [ ] Start with 1 AI squadmate and scale to the 8-slot squad: two fire teams of four, each with one medic and battle-buddy pairs.
- [ ] Add buddy pairing, a Throw intent (frag, flashbang, smoke), and Carry, Drag and treatment intents to `docs/squad_design.md` and the code.
- [ ] Rebind: Alt+G drops (G throws grenades), Shift+G cycles grenade type, and 1 to 9 pick command-menu entries only while a menu is open.
- [ ] Build the Arma 3-style F1 to F12 command interface, navigable with middle-mouse or 1 to 9.
- [ ] Add the movement and stance keys: F fire mode, X crouch, Z prone, C weapon mount, Q and E lean, and Ctrl+WASD stance adjust.
- [ ] Add ACE-style interaction: hold Left Windows for the radial menu on objects and people, and Ctrl+Left Windows for self-interaction.
- [ ] Keep voxel chipping as the visual, and add armor ratings, ceramic crack zones and plate integrity.
- [ ] Update `docs/squad_design.md` to name 8 slots as the target, and the README's locked decisions to match Captain's calls.
- [ ] Ai voice callouts preferred as well.

**Later phases**

- [ ] Phase 4, Mission loop: contract zones, then hot zones (several contracts at once, ends at extraction), the cash economy, and loot tiers by zone.
- [ ] Phase 5, Ground vehicles: the Blackhawk supports, AAVs, and the LHD on the coast or the FOB inland.
- [ ] Phase 6, Factions: territory that shifts between missions, reputation tiers, and enemy technicals and light vehicles.
- [ ] Medical depth when the roadmap reaches it: IV and IO with gauges, pressure bags, surgery kits, the four drugs, defib, and breathing simulation.

## Decided rules by system

Everything here is Captain's call unless marked (proposed), which means a starting value to tune in playtests. Full tables and numbers are in the design doc.

### Armor and ballistics

| Topic | Rule |
| --- | --- |
| Ratings | Rounds and armor share an NIJ-named ladder in the game's own order: IIA, II, IIIA, III, III+, III++, IV. Armor stops a round when its rating is at or above the round's level |
| Vests | Aramid-fiber soft armor. Light: IIA (proposed), front-only fragment protection, takes light plates only. Medium: IIIA (proposed), front and back, steel spall blocked at the neck only. Heavy: IIIA (proposed), front, back and sides, steel spall blocked at neck, face and arms |
| Plates | Light: stops regular .223 at most (III on the game ladder), bespoke to the light vest. Medium: III++ (proposed). Heavy: IV (proposed). Medium and heavy plates fit both medium and heavy vests |
| Plate materials | Ceramic cracks in about 5 cm zones, weakens with consecutive hits there and can shatter. Steel throws spall. Polyethylene is lightest (limits proposed) |
| Helmets | Aramid fiber and composite hybrid. Light IIA (proposed), medium IIIA (proposed), heavy III++ |
| Impact | Stopped rounds still deal impact (pain, knockouts). Impact kills only where it would in real life: a helmet stop can be fatal out to about 200 m, depending on the cartridge. Plate stops can crack a rib within 30 m for pistol, 100 m for intermediate and 200 m for full-power rifle rounds |
| Ballistics | Ammunition uses ACE3's ballistics values, checked in game |

### Medical (no hitpoints)

| Topic | Rule |
| --- | --- |
| Blood | Every unit has 6 L. Penalties to aim, stamina and speed scale with the share lost. Unconscious at 40% lost, cardiac arrest at 50% lost |
| Cardiac arrest | A 10-minute window for CPR, defib, drugs, fluids and treatment. With no heart rate, no pulse and a BP of 0/0 when it ends, the unit dies. Until then it counts as unconscious |
| Bleeding | Major arteries and the big veins (jugular, subclavian, femoral, vena cava) are simulated inside every body. A wound bleeds by how close the round passed to a vessel, multiplied by its cavitation |
| Body map | Lungs, heart, brain, arm bones, leg bones, other tissue, and penetrating chest cavity wounds |
| Breathing | Breathing, oxygen exchange and alveolar efficiency are simulated, and fluid in a lung or a collapsed lung lowers them |
| Treatment | Tourniquets, splints and vented chest seals. Surgery kits (2, 3 or 5 uses) clamp arteries with hemostats, the only field fix for torso arteries. A kit use can close a chest wound instead of a seal, with a 10% chance it reopens each time the casualty sprints, carries an extreme load, jumps or mantles |
| Fluids | Saline and blood, identical except for looks, in 250, 500 and 1000 mL bags. 500 mL takes 4 to 5 minutes through an 18 gauge IV. Gauges 10 to 20 are in the game: larger bores flow faster but are rarer, slower to place and more painful |
| IO and pressure bags | IO flows like an 18 gauge IV, or a 16 gauge with a pressure bag. Veins start collapsing at 37% blood lost; from then a pressure bag brings an IV back to 1.25x speed |
| Restarting a heart | Volume must be restored before CPR or defib can restart it. Only players and medics can defib or use surgery kits |
| Drugs | Only epinephrine, morphine, adenosine (slows a racing heart) and atropine (raises a slow one). No blood types and no heart rhythms |
| Enemy behavior | Enemies ignore unconscious foes and only dead-check when clearing or assaulting through |

### Squad, AI and death

| Topic | Rule |
| --- | --- |
| Squad | 8 slots, up to 4 human players, with AI filling the rest. One medic per fire team (two fire teams of four, proposed). Players pick their role |
| AI tactics | All AI, friendly and enemy, uses battle buddies and real infantry tactics modeled on LAMBS Danger.fsm and VCOM 3.4.0, including grenades, flashbangs and smoke |
| Downed friendlies | Out of combat, a buddy carries the casualty and follows the squad leader if a friendly dies we still carry their body to exfil to recover their body and gear. In a firefight, a squadmate may throw smoke, drag them to cover, then revive them or keep them safe |
| AI death | Permadeath on bleed-out. An AI squadmate left behind alive is MIA, with a recovery mission. A helicopter extraction counts as extraction |
| Player death | Respawn in the default kit: an M4, 2 spare mags plus 90 rounds, 1 smoke and 1 frag. The old gear stays where they died, with a map marker |

### Missions and supports

| Topic | Rule |
| --- | --- |
| Contract zones | Single contracts, with loot and salvage of at most medium-tier gear, scaled by difficulty |
| Hot zones | A larger, raid-like deployment holding several contracts from one faction, taken at once. No reputation minimum, but considerably harder. It ends when the squad extracts, and unfinished contracts lapse with a small reputation hit. Shares map regions with contract zones |
| Support rules | Available from the campaign start. Each call costs money and has a cooldown. Launched live from the LHD on the coast or the FOB inland. Aircraft and AAVs can be destroyed, losing their cargo and passengers |
| Resupply | Blackhawk drops a supply pallet at a grid coordinate or on green or yellow smoke, in any zone |
| Transport | Hot zones only. Lands at a grid coordinate or on green or blue smoke; with no smoke it loiters out of fire until it sees one. If resupply and transport are both inbound, the one called first takes the green smoke |
| AAVs | Transport, commandable through the command menu |
| Extraction | Evacuates HVTs, loot and deposited items from a grid coordinate or purple smoke, in any zone. Evacuated loot banks immediately. If the spot isn't safe (slope over 15 degrees, water, buildings or trees), it lands within 100 m. Enemy fire doesn't count as unsafe |

### Economy, world and feel

| Topic | Rule |
| --- | --- |
| Money | Contracts pay cash, which buys gear, repairs, medical supplies and support calls |
| Factions | Three factions. Territory shifts between missions. Enemies field infantry plus technicals and light vehicles |
| World | Day and night cycle, weather, and NVGs as gear |
| Difficulty | One realistic difficulty, with optional assists for co-op newcomers |
| HUD | Minimal, like Arma with ACE: no health bar or ammo counter |
| Weapons | Real-world guns with modular optics, lights, lasers, suppressors and grips |
| Inventory | Physical inventory measured in litres |
| Movement | Movement has weight: momentum into starts, stops, turns and stance changes, made heavier by load |

## Controls

All keys below are Captain's calls, and all are rebindable. Keys not listed keep the README's current bindings.

| Key | Action |
| --- | --- |
| G | Throw the selected grenade |
| Left Shift + G | Cycle grenade type (frag, flashbang, smoke colors) |
| Alt + G | Drop the carried bulky item or active weapon |
| H | Use medical item (unchanged) |
| F | Change fire mode |
| X | Crouch |
| Z | Prone |
| C | Mount the weapon on a surface for stability and recoil control |
| Q / E | Lean left / right. Hold to lean, double-tap to stay leaned, tap again to return |
| Ctrl + W / S | Step stance up or down in fine steps, as in Arma 3 |
| Ctrl + A / D | Shift stance to the side, as in Arma 3 |
| Left Windows (hold) | ACE-style interaction: action points and radial menus on objects, vehicles and people |
| Ctrl + Left Windows (hold) | ACE-style self-interaction for your own body and gear |
| F1 to F12 | Arma 3-style command interface: select squadmates and open command and support menus |
| Middle mouse or 1 to 9 | Navigate command and support menus. Outside a menu, 1 to 9 switch weapons |

## Still open

None of these block phase 3.

- [ ] Confirm respawn ammo: read as 2 spare mags plus 90 loose rounds, not 90 rounds total.
- [ ] Do AAVs deploy from the FOB in inland zones? Proposed: yes.
- [ ] Check whether X, Z and C clash with existing build bindings, and settle any clash with Captain.
- [ ] Reputation tiers, allied troop types, and what limits the allied-troop support menu (phase 6).
- [ ] The player-built faction: what it involves, and whether it replaces or sits beside contracts (stretch goal after phase 7).

**Starting values to tune in playtests** (all in the design doc): vest, helmet and medium and heavy plate ratings; ceramic crack size and stop-chance loss; blood loss effect curves; bleed rates and the cavitation falloff with distance; surgery kit clamp time (about 20 s) and defib shock time (about 5 s); IV gauge multipliers and placement times; weapon mount bonus (about half the sway and recoil); stance heights; and movement start and stop times.
