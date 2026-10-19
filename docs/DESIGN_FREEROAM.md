# Free roam: Street Legal outside a career (design note, draft)

Goal: in free roam the phone and the SL features work through Mods-menu switches, off by default, and a career save is never read or written.

## Decisions (62, 2026-10-19)
- One shared helper replaces the ~35 one-line `career()` helpers (one change per module). `sl_mode.enabled(feature)` answers "may this feature run now?"; `sl_mode.state()` returns the career state in a career, the sandbox state in free roam, else nil.
- The sandbox state lives in its own file (`/settings/street_legal/freeroam.json`), never in a career slot (`career.lua` SAVE_DIR/slotFile).
- Money is Wrench Works' free-roam balance (Mods > Wrench Works > Money > Freeroam money; `garageParts` `save.wallet`). No second wallet: the sandbox state holds no cash, the wallet calls read and write WW's.
- Owned cars in free roam = the cars the player spawns. Garage = the WW home garage only. Rep, rivals and the campaign stay off.

## Helper
```
sl_mode.state()          career state | sandbox state | nil
sl_mode.enabled(f)       career active (as now) | (free roam and the Mods switch for f is on and f is in FREEROAM_OK)
sl_mode.kind()           'career' | 'freeroam' | nil
```
Each module's `local function career()` becomes `return sl_mode.state()`; modules that check `sl_career.has('x')` call `sl_mode.enabled('x')`. Pure core in `sl/core/mode.lua` (table of features, tested by luatest); the GE wrapper reads the switches.

## Feature split (first pass; to be settled with 9e for the UI side)
| Feature | Free roam? | Notes |
|---|---|---|
| Phone, Maps | yes (9e) | apps that need rep/garage hide |
| Weather / wet world | yes | no state needed; own switch |
| Places and pins (shops, gas, wash, hospital) | yes where the map has `/street_legal/places/`; else the level's facilities | own switch |
| Shops, parts, tyres, car wash | yes | pay from WW balance |
| Traffic | yes | own switch |
| Cab, jobs (day-job board), wwjobs | yes | rewards go to WW balance; no rep |
| Races (drag, street), spectators | yes | no rep, no rival challenges |
| Police | optional, own switch | heat is sandbox-only, resets with the session |
| Rep, rivals, crews, clubs, classifieds, auctions, dealers, bank, achievements, campaign | no | need career-only data |

## Open
- Which maps: SL places exist per career map only; other maps get facility-based pins only (needs a check).
- Whether WW's wallet is reachable from SL GE Lua (a cross-mod call); if not, a small getter in the Wrench Works repo.
- Not checked: any module's use of career-only fields beyond the grep of `isActive()`. Nothing was run.
