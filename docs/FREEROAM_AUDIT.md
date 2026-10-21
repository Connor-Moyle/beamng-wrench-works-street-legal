# Free-roam audit: what Street Legal writes into other mods, and what runs without a career

Street Legal 0.6.0 lets a few features run in free roam (Mods menu > Street Legal > Free roam, every switch off by default: `sl/core/mode.lua`, `sl/mode.lua`). This audit lists every place where Street Legal changes another mod's state or a file, says whether that place can run in free roam, and names the test that holds it: `tests/freeroam_audit_test.lua` (run by `tools/luatest.js` after `tools/luatest.lua`), next to the strict career test in `tools/luatest.lua` ("free roam never writes a career").

## The rule

In free roam there is no career (`sl_career.isActive()` is false, `sl_career.getState()` is nil). `sl_mode.state(feature)` gives the features a sandbox table (seed, day, phase, hour, `sandbox = true`) that is never saved and carries no money, cars, rep or garage. Every module that spends, sells, stores, repairs or saves reads the career state first (`local function career() ... end` in 36 modules) and returns when there is none.

## Street Legal → another mod (writes)

Every call that changes another mod's state. "Free roam" says whether the call can happen with no career.

| Where | Call | Guard | Free roam |
|---|---|---|---|
| `sl/career.lua:336` (`connectWallet`) | `slrr/garageParts.setMoneyProvider(wallet)` — Wrench Works' garage spends from and pays into the career | called only from the career's start (`:749`, with the wallet) and stop (`:871`, with nil) | never: no start without a career. Without a provider Wrench Works keeps its own money |
| `sl/races.lua:114` (`changeMoney`) | `slrr/garageParts.changeMoney(amount, label)` — a bet settled through Wrench Works | the sprint races are career-only (`finish` runs inside a race the career started) | never in 0.6.0; **when races come to free roam (0.6.1) this call must stay behind a career check: a free-roam bet has no wallet** |
| `sl/classifieds.lua:155, 276, 487, 558, 573, 591, 676` | `slrr_garage.addShelfPart / putShelfItem / takeShelfItem` — parts bought, sold, returned | every entry (`summary`, `buy`, `listPart`, `acceptOffer`, `withdraw`, `buyAtMeet`, `bid`, `onUpdate`...) starts with `career()`, which also needs `sl_career.has('classifieds')` | never |
| `sl/computer.lua:123` (`enterGarage`) | `slrr_garage.enterWith(vid, mode)` — the laptop sends a car into the garage | `careerOn() and at and sl_career.getState()` | never |
| `sl/fleet.lua:333` (`setActive` → work) | `slrr_garage.enterWith(vid, 'work')` | the career state `s` | never |
| `sl/phone.lua:308` (`catalog`) | `slrr_garage.enterWith(vid, 'catalog')` | `career()` (the phone is a free-roam feature; each of its garage, car, money and replay entries checks the career itself) | never |
| `sl/phone.lua:327` (`saveClip`) | `sl_replay.save()` — a replay file | `career()` | never |
| `sl/services.lua:85, 103, 113, 132, 145` | `slrr_garage.leave() / enter()` — the garage closes for an event or a swap | the career's services (`career()`) | never |
| `sl/upgrades.lua:35` (`push`) | `slrr_garage.setFeatures(f)` — what the career's garage has (lift, crane, dyno...) | `M.features()` is nil without a career, so the call is `setFeatures(nil)`: Wrench Works' own default, a clear, not a state change | the clear only |
| `sl/upgrades.lua:73` (`onStreetLegalStopped`) | `slrr_garage.setFeatures(nil)` | — | the clear only |
| `sl/wwjobs.lua:185` (`onUpdate`) | `slrr_garage.markJobCar(vid)` — a customer's car sells for nothing | `active()` needs a career job | never |
| `sl/activities.lua:82, 84` (`helmetForEvent`) | `slrrDrivers.setAppearance(vid, { helmet })` — a helmet for a race event, put back after | called with `true` only from a career race kind (`:120`); the `false` calls (`:90`, `:97`) restore only what was set | never |
| `sl/fleet.lua:109, 110, 142, 149` | `sl_tyrecare.save(vid, car)`, `sl_surfacefx.save / repair / wash(vid)` — the tyres' wear and Car Surface FX's dirt kept with a career car | the career's car record | never (and Street Legal's own modules, writing into the career state, not into the other mod) |

## Files Street Legal writes

| Where | File | Free roam |
|---|---|---|
| `sl/career.lua:165-198, 294, 636-637` | `/settings/street_legal/career*.json`, `slots.json`, `places.json` (the saves) | never: written by the career's start, save and delete |
| `sl/options.lua:242, 279` | `/settings/street_legal/options.json` (the Mods menu, the free-roam switches themselves) | yes, when a setting changes |
| `sl/hud.lua:58, 77` | `/settings/street_legal/hud.json` (the HUD layout) | yes, when the player moves the HUD |
| `sl/photos.lua:22-94` | `/settings/street_legal/photos/` (photo mode's pictures) | yes, when a photo is taken |
| `sl/markers.lua:79`, `sl/puddlefx.lua:156, 163, 221, 277` | `/temp/street_legal/shapes/*.dae` (flare and puddle meshes) | yes: scratch shapes, not state |

## Other mods ↔ Street Legal

- **Nobody outside Street Legal listens to an `onStreetLegal*` hook.** Street Legal fires 26 of them (`onStreetLegalChanged` from 71 places, `Started`, `Stopped`, `BeforeSave`, `Spent`, `CarSold`, `CarDelivered`, `RaceResult`, `RaceStarted`, `RaceTimed`, `RaceCancelled`, `Phase`, `PhaseEnded`, `NewDay`, `Weather`, `Option`, `Text`, `Fade`, `PlacesChanged`, `GarageMoved`, `DistrictTaken`, `KingOfValo`, plus `onSlrrRaceStarted / Finished / PinkCarDelivered`); the listeners are Street Legal's own modules and the QA probes in the control repo (`tools/qa_game/probes/`). Wrench Works, Drivers, Part Wear, the Valo map and Car Surface FX were searched (2026-10-21).
- **Other mods read Street Legal** and never write it: Wrench Works `slrr/garage.lua:1976` (`sl_career.phase()`: the garage is closed at night), `:254, :1073-1103` (`sl_fleet.carOfVehicle`, `sl_fleet.despawn` when a career car is stored: `despawn` itself returns without a career, `sl/fleet.lua:296`), `slrr/settings.lua:301` and `settingsCheck.lua:41` (`sl_career.isActive()`); the Valo map `slrrValoRaces.lua:63` (`inCareer`); Drivers `slrrInjury.lua:480` (heals when no career) and `slrrPedestrians.lua:1203`; Part Wear `slrr/partwear.lua:67` (`sl_fleet.carOfVehicle` for a car key).
- **The wallet** exists only while a career runs: Wrench Works' `garageParts` asks its provider for money (`:134, :197, :211, :229, :1069`) and has none without `setMoneyProvider`, which only the career's start gives.

## The test

`tests/freeroam_audit_test.lua`: every switch on, no career, every one of the 56 `sl/*.lua` extension modules loaded against a stubbed game (unknown globals are stubs whose calls return nil, so a hook takes its early exits; Wrench Works' `slrr_garage`, `slrrDrivers` and `slrr/garageParts` are recorders), every `on*` hook of every module called twice with the game's argument shapes (558 calls), then: no career started; no shelf, garage, driver or wallet call reached another mod; the only files written are the HUD and options settings, photos and temp shapes; no career, money, sale, race-result or rival event fired; the sandbox state of each free-roam feature has no money, cars, rep or garage; the career-only features stay disabled. A planted `slrr_garage.addShelfPart` makes it fail (checked by hand). `tools/luatest.js` lists the modules from the folder, so a new module is audited the day it is added.
