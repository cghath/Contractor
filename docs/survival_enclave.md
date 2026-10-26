# Contractor: Fallen: the enclave, ARCHE's trail, the bunkers, the cure's places

Phase C lane `claude/survival-enclave` (survival_world.md sections 6-7, survival_medical.md section 3;
calls 15, 24, 46, 56, 62, 66, 68, 99). Built on the world sim. Every number is **Proposed** and lives
as a const at the top of its file or in the data files.

## What's built

- **`FallenStory`** (scripts/survival/fallen_story.gd): the one place WorldSim calls the lane from:
  `server_setup(m)` at the end of `WorldSim.server_setup` (or lazily on the first far tick of an older
  world) and `server_after_step(m)` at the start of `WorldSim._after_step`, so the lane's events join the
  step's events (journal, `event_added`). The lane's state sits **beside** the world section
  (`Survival.state()["enclave"]`, `["arche"]`, `["bunkers"]`, `["cure"]`), so a far tick out on the
  worker never overwrites it. Calls from the players' side change the world through `WorldSim.mutate`
  (`FallenStory.world_do`, `FallenStory.event`).
- **`Enclave`** (enclave.gd) + **`EnclaveDetachment`** (enclave_detachment.gd) + **`EnclaveNode`**
  (`Survival/Enclave`, `is_quartermaster(rec)` for the intel/trade lane):
  - the one enclave group (WorldSim's evac group; in clear-the-map it's made here as a plain faction);
    **posts** at the port and the military base (the first zones of those types; the evac's is home)
    and **patrols** (3 people each) walking routes between them and around the posts, a zone per 8 far
    ticks (2 h); three **officers** (Major/hard, Lieutenant/decent, Sergeant/frightened) as named
    Persons with standing toward the players; a **quartermaster** Person.
  - **tolls**: far groups in a held zone pay 10% of their food, ammo and fuel once a day (corrupt: 20%),
    or are turned back (the enclave hates them, or a cruel raider crew); the players at a held zone
    (or a patrol at their settlement) get a $100 toll (corrupt $200): the council's question at the
    settlement (its stores pay), else a journal line and a message, answered with
    `Enclave.server_answer_toll(id, "pay" | "refuse", s)` (food, meds, ammo from his kit first; never
    guns or armour). Refusing: turned back, standing -15.
  - **looters**: a group foraging in a held zone gets a far fight (`WorldFights.resolve`), once a day.
  - **trade**: daily with settlers it trusts (both ways 30+): 1 meds and 1 fuel for 4 food; a settlement of
    7+ sends a person now and then (20%). Trust is seeded at setup (settlers within two zones of a post, 60%).
  - **nature by seed** (`Enclave.terms_for(seed)`): honest (evac real), corrupt (evac real 60%; prices
    and tolls up), collapsing (evac real 70%; loses a person on a day at 35%).
  - **the price by seed**: the cure (a serum dose or an immune person: `server_deliver`), a convoy
    base-to-port escorted (`server_start_convoy`; risk 35% a zone unescorted with a horde or raiders),
    a settlement's loyalty (`server_hand_over(group_id)` or the council for the farm), conscripts
    (`server_conscript(pids)`, 2; corrupt 3). Progress via `server_progress`; `server_pay_price` calls
    `WorldSim.server_set_evac_paid(true)`, or, when the evac was a lie, takes the price and says so.
  - **infiltrate**: `server_wear_disguise(s)` with `enclave_uniform` + `enclave_pass` carried: the
    enclave's standing with the players reads 40 (friendly stance, live and far) until a check fails
    (`server_check_disguise`: 15%, +15% with the hard officer alive and cool to you, -10% when the
    frightened one likes you; checked at tolls). Blown: standing 25 under where it was.
  - **break**: the home post down to nobody (live kills through `server_kill(pid)`, far fights): the
    enclave is broken, `goal.port_taken` and `goal.price_paid` set (WorldSim.goal_state keeps the evac
    open through port_taken), the rest fall back to the other post.
  - **join** (call 68): `server_join(s)`: no tolls on the players, enclave standing +50, every other
    group -15 (-25 for its enemies), three tasks as journal lines (patrol, escort, toll), companions with
    a conscience (kind or loyal) get a -12 moodlet and leave at 35% (a desertion break), the enclave's
    part of ARCHE's trail is learnt.
- **`ArcheTrail`** (arche_trail.gd, data/arche_trail.json): 16 pieces (notes, terminals, recordings,
  two broadcasts, the technician, the officer's story) laid by the seed over the sites (the lab, the
  sealed level at the base, the bunkers, two relay stations, Quarantine Camp 2, the technician's place,
  the enclave) in a seeded order; six pieces carry a bunker's code. `server_read(id, s)`: a journal
  line, a map mark at the piece and one where the trail leads next, the code learnt; shared to the
  intel lane in `Survival.state()["trail"]` (`pieces`: {text, day, zone, ...}; `numbers`: the numbers
  station's lines). Broadcasts air once a world day as events of kind `broadcast` with `freq`
  ("4.625 MHz") and `piece`. Two theories (leak, release) stay open (`theories()`). The technician is a
  lone survivor flagged `arche_survivor` (and immune). ARCHE items: `arche_dossier`, `arche_tape`
  (read through `server_read_item(s, id, state)`).
- **`Bunkers`** (bunkers.gd, data/bunkers.json): 3-6 a world, never in the farm's zone or the city, a
  door record 18 m off a place; opens by its code at a powered keypad (`server_power`: a vehicle
  battery or a jerrycan, or `free` for a wired generator), a cutting torch, or a breaching charge (loud:
  +30 pressure); rooms from four prefabs with loot tables (serum in the rare tiers), a trap or two
  (tripwire: noise and +15 pressure; gas: +25 taint on the survivor record), sealed dead 40% (3-8, 30%
  hazmat) let out at the door, a survivor 20%; always a trail piece (or a fragment). Opened: a
  `bunker_opened` event; raiders in its zone claim an opened one at 25% a day. Live: the rooms are
  WorldCaches at the door.
- **`Cure`** (cure.gd): the lab zone's centrifuge, fridge and power (markers at its first place; power
  from a jerrycan or a battery); the immunity roll (3% a person, at least one in the world; the
  technician); `server_make_serum(s, donor)` gated by Rpg's `cure_chain` (medical 9), at the lab
  powered, an immune donor with him (companion, settler, or out there in the lab's zone): a `serum`
  dose; `server_test_blood(pid)`; `server_apply(s, rec)` clears `bitten` / `bite_day` / `fever` for
  phase D's clock. Serum also in the hospital, lab and bunker tables (data/bunkers.json,
  `Bunkers.roll_table`).
- Items: `serum`, `enclave_uniform`, `enclave_pass`, `cutting_torch`, `arche_dossier`, `arche_tape`
  (items.json, prices.json).
- Suite: `enclave` (tests/enclave_test.gd).

## What's left

- The bunker interior as geometry (rooms stamped under the door): today the rooms are caches at the door.
- UI: the toll's pay/refuse buttons, the officers in the talk menu, the price and tasks on the journal,
  wearing the disguise from the inventory, reading ARCHE items from it (the APIs are there).
- Live enclave bodies at posts and patrols (WorldLive shows the group; patrols as their own live squads).
- The convoy as a live column; taint's effects (call 99's meter); the hospital zone (no zone type yet).
- Players who refuse a toll and stay: the patrol's attack (today only standing falls).
