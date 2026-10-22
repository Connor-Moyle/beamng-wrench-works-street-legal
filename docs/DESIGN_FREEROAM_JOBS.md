# Jobs in free roam (design note, a5, for sign-off; nothing built)

Audit row: "Jobs and races in free roam" (DESIGN_FREEROAM 0.6.1, FREEROAM_AUDIT). This note cuts the first step so small that it can be tested offline and cannot touch a career.

## What I found
- `sl/jobs.lua` is 845 lines and reads the career state in about 19 places (`career()`), pays through `sl_career.payOut`, writes rep (`stateLib.addRep`), heat, the sponsor, the crew contract and texts to rivals. Most of the kinds need the career map's own place files (`sl_career.getPlaces()`), which are only loaded when a career starts, so in free roam a courier or part run has **no stops**.
- The stops that DO exist in free roam are the stock delivery businesses and the gas stations (`freeroam_facilities`): the new Freight run and the diner food run read exactly those and need nothing from the career.
- Free-roam money is Wrench Works' wallet (`slrr/garageParts.changeMoney`, already used by `sl/races.lua`).

## Step 1 (proposed): freight runs in free roam, nothing else
- `sl_mode` gets a feature id `jobs` (Mods > Street Legal > Free roam > Jobs, off by default, needs the master switch).
- A separate small extension `sl_frjobs` (about 150 lines) does the free-roam board: it does NOT run `sl_jobs`. It reuses the pure rules (`core/jobs.freight`, `shown`, `settle`), the stock sites (`jobs.deliverySites` moved to a shared helper `sl/core`-side reader in a new file), the markers/route (`sl_markers` / ground markers as `sl_jobs` does).
- Board: up to 3 freight offers, rebuilt at each game-clock day/phase change (the sandbox state of `sl_mode`), shown on the phone's Jobs page through a snapshot field `frjobs` (9e adds the card; fixture + `phone_audit` per the rule).
- Pay: `garageParts.changeMoney(amount, label)` only. No rep, no heat, no sponsor, no first-jobs bonus, no new-in-town boost, no contract terms, no tow/taxi/part/courier kinds, no text to anyone.
- Damage and lateness settle with the same pure `settle`.
- Nothing is saved: the active job and the board live in the session (the sandbox), like the rest of free roam.
- Settings: reuses `slFreightPay` and `slFreightMin`; its own switch only.

## Why not refactor `sl_jobs` to take a sandbox state
Every one of the 19 reads and the rep/heat/sponsor/crew writes would need a sandbox guard, and a missed guard writes a career event in free roam (what the free-roam audit forbids). A second 150-line module has none of those writes by construction, and the audit test (`tests/freeroam_audit_test.lua`) can assert it never calls `sl_career`, `writeSave`, rep or heat.

## Later (not in this step)
- Diner food runs at night (stops = gas-station diners; kerb stops need the road graph box that the career's places define: check `kerbNear` without places).
- Races in free roam: `sl/races.lua` bets already go through `changeMoney`; needs the rival-free "stranger" race from DESIGN_FREEROAM (a separate note).
- Courier/part runs: only if the places can be read per level in free roam.

## Tests
- Pure: nothing new (freight/settle exist).
- `luatest`: a free-roam session with the jobs switch on and no career: a board of freight offers from a stubbed facilities list, accept/complete pays through a stubbed `changeMoney` once, never calls `sl_career.getState/payOut`, never fires a rep/heat/rival hook, never calls `FS:`/`jsonWriteFile`; the freeroam audit loads the module with every switch on.
- Game proof (80): free roam on West Coast, switch on, a Freight offer on the phone, deliver, the Wrench Works balance rises; career save checksums unchanged.

## Questions for 62
1. Is "freight only" the right first step for free-roam jobs (courier/part/taxi stay career-only)?
2. A separate `sl_frjobs` module (my recommendation) or the sandbox guard refactor of `sl_jobs`?
