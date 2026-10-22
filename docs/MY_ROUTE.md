# My route (campaign idea #14)

Status: design, nothing built. Switch: "My route" on Active features, off by default.

## What the player does

1. Phone > Races > My routes > **New route**.
2. Drive to a place and press **Drop waypoint here** (4 to 8 points; **Undo** takes the last one back). The first point is the start, the last is the finish. Name it, **Save**.
3. A saved route shows its length, its best time and the number of runs. **Race it**: drive to the start; the clock starts when you pass waypoint 1 and stops at the last. The next waypoint has flares and a ground-marker path leads to it.
4. The best time per route is kept in the career save. No sharing, no money, no reputation (a 60 m route would be a money tap).

## Reuse

- Flares: `sl_markers.flareCircuit` (checkpoint posts either side of the road).
- Gate test: the crossing test of `sl/core/traps` (a point is passed by crossing its gate line, or by coming within 12 m).
- Save and hooks pattern: `sl/traps.lua` (per-level entry in the career save, `onUpdate` throttled to ten times a second, only the next waypoint tested).
- Phone page pattern: the Speed traps page.

## New code

- `sl/core/myroute.lua` (pure, tested): limits (4..8 points, 60 m apart at least, 15 km at most), validation with the reason, name cleaning, progress state machine (next index, passed test, order enforced, a teleport over 80 m cancels the run), best-time record (`best`, `runs`, `last`), time formatting.
- `sl/myroute.lua` (game side): the editor (drop, undo, save, delete), the run (start on waypoint 1, flares and path to the next, finish), save under `s.myroutes.levels[level]`, `summary()` for the phone, feature gate `myroute`.
- Phone: one page in slPhone.js (list, editor, run state).

## Ghost

Not in v1. The only recorder is `core_replay` (a whole-game replay file), not a light position track; a ghost car would need our own recording and a visual-only vehicle, which 0.40 does not allow (see the Impostor cars note). Offering "watch my best run" through the replay file is possible later but costs a file per route.

## Map picking

The Maps app is the better place to pick points. Version 1 does not depend on it: points are dropped where the car is (this is also exact: the point is on a road the car drove). A later version can add "Add to route" on a Maps pin. To agree with 9e: the Maps app exposes the pin's position to my module.

## Tests

luatest: limits and validation, gate crossing in order and out of order, teleport cancel, best-time record, formatting, feature off means no hooks. Offline phone test for the page (jsdom). In-game: a TEST_MATRIX row via ab.

## Questions

- No pay and no rep: agreed? (A route is chosen by the player, so paying for it is exploitable.)
- A cap of 10 saved routes per map: agreed?
