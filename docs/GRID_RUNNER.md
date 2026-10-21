# The grid runner (sl_gridrace)

A race meeting on a closed layout the map brings, run by the game's own race object (`lua/ge/extensions/gameplay/race/race.lua`). The calendar's weekend races use it; the brand invitationals and the home events of the series are meant to reuse it. Rules in `sl/core/gridrace.lua` (pure, tested); the game side in `sl/gridrace.lua`.

## What a run does

1. Fade to black. The layout's `mainPrefab.prefab.json` (barriers, markings) is placed with `spawnPrefab`.
2. The player's car is moved to the layout's default start position (no repair: the car as it is), frozen.
3. The field: the player's performance class (`gameplay_vehiclePerformance.getClassFromVehId`), then 3 to 7 cars (the `slGridCars` setting; the Performance preset 3) from the AI pool in that class, the classes next to it when it runs short, distinct models first. Each is built on its grid spot one at a time under the shared black-time budget (`job.slFadeT0`, 12 s): what does not fit is left out. The SLRR opponent drivers sit in them.
4. The flares mark the layout (the Street Legal markers option). Fade up, the layout's `introFwd` camera path (up to 8 s; `slGridCams` off skips it), a 3-2-1 countdown, go: the race object starts, each AI car drives the layout with `ai.driveUsingPath` at an aggression from the player's reputation (0.55 at 0, 0.95 from 2000).
5. The laps (3 by default). When the player's state is complete the place is the race object's placement at that moment; a race over 15 minutes is a DNF.
6. The result on screen, the `finishFwd` camera path (up to 5 s), the AI cars deleted, the prefab removed, the flares cleared, `done(result)`.

## API

```lua
local ok, text = sl_gridrace.start(spec, done)
-- spec = { layer = '003', name = 'Dockyards 3-lap sprint', laps = 3, purse = 800 }
--   layer: a West Coast dockyards layout (levels/west_coast_usa/gameplay/trackLayers/dockyards/<layer>/), or
--   dir = '/levels/<level>/<folder>/' with race.race.json, mainPrefab.prefab.json, introFwd.camPath.json, finishFwd.camPath.json
-- done(result) is called once: { place = 1.. or nil, time = seconds, grid = cars on the grid, aborted = true|nil }
sl_gridrace.abort()      -- a career stop, a level end or a vehicle change ends the race; done gets { aborted = true }
sl_gridrace.running()    -- the running spec or nil
sl_gridrace.status()     -- a line for the console
```

The runner keeps no career state: the caller pays the entry, the purse and the reputation (`sl/core/gridrace.payout(place, purse)`: the purse to the winner, half to second, a quarter to third; 40/20/10 reputation, 5 for a finish).

## Not seen in the game yet (80's block)

- The AI finish 3 laps on each of the six layouts (the dockyards loops are 450 to 810 m; the AI path is the race object's own).
- The stall count while the grid builds (one car at a time behind the fade) and the frame cost with the full grid of 7.
- The prefab appears and disappears; the camera paths play and hand the camera back; the player's car is not repaired by the move to the grid.
- The place reported matches what the player saw.
