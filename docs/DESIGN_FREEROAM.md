# Free roam: Street Legal outside a career (design note)

Goal: in free roam the phone and the SL features work through Mods-menu switches, off by default, and a career save is never read or written. Written by a5 (world/career side) and 9e (UI side), merged. For SL 0.6.0 / Wrench Complete 0.10.0. Plan only; nothing is built yet.

## Decisions (62, 2026-10-19)
- **Switches**: ESC > Mods > Street Legal > Free roam: a master switch "Use Street Legal features in free roam" and one per feature. All off by default, so nothing changes for a player who does not opt in. The master alone enables nothing; a feature needs both.
- **Helper**: one shared helper replaces the ~30 one-line `career()` helpers (one change per module). `sl_mode.enabled(feature)`, `sl_mode.state(feature)`, `sl_mode.kind()`.
  - In a career: `enabled` is true and `state` is the career's state, exactly as now.
  - In free roam: `enabled(f)` needs the master and the f switch; `state(f)` is the **sandbox state**, a `state.new()` that is never passed to `writeSave` and never written to a career slot.
  - A career-only feature asks `sl_mode.enabled(f)` with f not in the free-roam list; it is false there whatever the switches.
- **Sandbox file**: the sandbox's own choices live in `/settings/street_legal/freeroam.json` (not a career slot, not `career.lua` SAVE_DIR slot files), so they survive a restart. Nothing from a career goes into it, and nothing from it into a career.
- **Money**: Wrench Works' existing free-roam balance (Mods > Wrench Works > Money > Freeroam money; `garageParts` `save.wallet`). No second wallet; the sandbox state holds no cash of its own. If the wallet is not callable from SL GE Lua, add one getter/setter function to the WW repo, with a test; that stays in the plan.
- **Cars and garage**: owned cars = the cars the player spawns. Garage = the WW home garage only. Rep, rivals and the campaign stay off.
- **Clock**: the clock follows the game's time in free roam. An opt-in switch lets SL control it. SL never moves the time of day on its own in free roam.
- **Maps**: SL's place files exist per career map. Other maps get facility pins only (`freeroam_facilities`).
- **Safety**: every career-only write is a no-op in the sandbox. A luatest asserts a free-roam session never calls `writeSave` and never fires rival or heat events. A crash handler must not write a save either.

## Features
| Feature | Free roam | Why |
|---|---|---|
| Phone (K) with its apps | yes, a subset | the shell reads the state for messages, money and the day; apps of the career's story (rivals, pink slips, campaign, rep, owned garages) stay off |
| Maps app, HUD phone | yes | road graph, player, places; not the career state |
| Big-map pins (our places) | yes | `pois` works from the place list; only its "career on" check changes |
| Weather, wet roads, puddles | yes | need the level and rain, not the career |
| Clock, day/night | yes, game time | see Clock above |
| Traffic density | yes | a setting of ours |
| Car wash | yes | car plus WW money |
| Shops (Wrench Works), tyres | yes | WW free-roam money |
| Cab | yes | road graph and places |
| Dashboard HUD | yes | `hud` has a free-roam switch already |
| Jobs, wwjobs | 0.6.1 | pay into WW money; no rep, no heat |
| Races, meets, spectators | 0.6.1, a subset | a race against a stranger for money; no pink slips, rivals or rep |
| Police | optional later | heat is sandbox-only and resets with the session |
| Saves, progression, rivals' story, hospital bills, rep, crews, clubs, dealers, bank, classifieds, auctions, pink slips, campaign end, tutorial, achievements | no | one persistent career's data |
| Drivers, Driver Injuries, Car Surface FX | already work | only the pedestrians ask whether a career is active (`slrrPedestrians.lua` ~1203); 80 confirms in game |

## Release split
- 0.6.0: `sl_mode` and the settings, the zero-risk features, the phone subset, Maps, weather, shops/wash/cab.
- 0.6.1: jobs and races.

## Work order
1. `sl_mode` (pure core `sl/core/mode.lua` plus a GE wrapper) and its luatests; the audit of career-only writes.
2. The one-line swap in the modules, zero-risk ones first (Maps, pins, weather, traffic, wash, cab, hud).
3. Phone with the sandbox state, then WW shops, then the clock switch.
4. Jobs, then races.

## Tests and proof
- luatest for `sl_mode`: off by default; master alone enables nothing; a feature needs both switches; the sandbox state is not the career state and is never offered to the save; career-only features are false in free roam; in a career behaviour is unchanged; a free-roam session never calls `writeSave` or fires rival/heat events.
- 80 proves it in free roam on West Coast: the phone opens, the map works, rain and wet roads, and the career save files' checksums are unchanged.

## Risks
- Each module may have writes that assume a career (a message to a rival, a heat change): the audit must list them. A sandbox that quietly takes a write is fine; one that fires a career-only event is not.
- Phone data pushed to the UI (`sl_uipush`) assumes the state exists; with the master off the phone must not appear.
- Not checked: any module beyond a grep of `isActive()`; nothing was run.

## Audit of career-only writes (a5, step 3)
- **Save files**: only `career.lua` writes a career. `writeSave` (local) returns at once with no state (`if not s`), its callers are start, stop (guarded by `active`), the autosave in `onUpdate` (guarded by `dirty` and `s`) and one more at the end of a path in the 1470 range. Free roam never sets `s`, `active` or `dirty`, because `sl_mode.state()` is a separate sandbox (step 4), never the career's. Other writers: `hud.json` (the HUD's own settings), `options.json` (the Mods switches, global), `photos` (`WALLS`, the wall photos). None of them is a career file; they are the same in free roam.
- **Test**: `tools/luatest.lua` "free roam never writes a career": loads the real `sl/career.lua`, switches every free-roam feature on with no career, runs every `on*` hook of the career module several times, and asserts no `FS:` call, no `jsonWriteFile`, and no rival, heat, start or save event. A hook that starts writing without a career fails it.
- **Remaining work for step 4**: each module that reads `sl_career.getState()` (about 35 files; `phone` 49 uses, `fleet` 22, `streets` 20, `jobs` 19) must either be career-only (`sl_mode.enabled(f)` false in free roam) or handle `state == nil`/sandbox. The swap goes one module at a time, zero-risk first.
- Not checked: modules that write through another mod's API (Wrench Works wallet, `slrr_garage`); events other mods hook (`onStreetLegal*`) are not audited yet.
