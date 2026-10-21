# Wet roads and walls and the High-graphics device loss (BeamNG 0.40)

Status: parked (2026-10-21). "Wet roads and walls" (slWetWorld) is off by default since 0.6.1, with a warning in its Mods row. This note keeps the evidence so Connor or BeamNG can pick it up.

## What happens
On BeamNG 0.40, in heavy rain, with Wet roads and walls on, the game loses the graphics device ("d3d12 ... device removed during swap chain present: 0x887a0006", "The GPU stopped responding and was reset"). The Lua log goes silent for several seconds before the line, so the hang starts before the crash is reported. Not an out-of-memory failure: the "texture allocation failed" lines come after the device is lost.

## The runs (all on an RTX 3080 Ti, QA career on west_coast_usa, forced heavy rain from a forced clear)
| Run | Graphics | Wet world | Car | Result |
|---|---|---|---|---|
| 0.5.1 (before the gate) | Low | on | - | crashed 4 of 4 with puddle planes |
| gate + pace builds | Low | on | - | survived (long runs) |
| 21:11 | Connor's High/Custom | on | - | crashed 2 s into the reloads, before any puddle plane existed |
| (b) 899afa9, 1 edit per batch | High/Custom | on, 10 puddles | driving legs, teleported back with a reset | crashed 78 s into the rain |
| (a) 899afa9 | High/Custom | **off**, puddles on | - | survived 628 s |
| trace 63fb2a8, standing | High/Custom | on, trace on | standing still | survived all 308 edits (109 s) and 180 s |
| trace 63fb2a8, driving | High/Custom | on, trace on | reset onto a street, then driven | crashed 52 s into the rain, after 11 of 308 edits |

## The 11-edit crash (crash_2026-10-21_2251_highrain_wettrace_63fb2a8_driving.log in the graph repo's crashlogs)
- Edits #1-#11 were all asphalt, the last at 211.88 s; no "wet start" without its edit afterwards, so no edit was running at the hang. The next Lua log line is the device loss at 217.14 s: a 5.3 s silence.
- The car was rebuilt just before: slrrDrivers logged the autobello's wheel at 209.16 s, "parts that fell off" at 209.72 s; the first edit was at 209.59 s. So a vehicle reset/respawn happened about 0.4 s before the first edit and 2.7 s before the stall (the reset is in the first seconds of the edits, not at the moment of the stall).
- The plan had 332 materials (glass 35) where the standing runs had 308 (glass 11): the car's materials seem to enter the plan when the car exists, although `classify` skips files under /vehicles/. Unchecked: which 24 glass materials these were.
- One misclassification seen in the trace: a tree imposter material (`imposter_mat_levels_west_coast_usa_art_shapes_trees_trees_conifer_redwood_broad.dae`) counts as asphalt.

## What it is not
- Not VRAM exhaustion (no allocation failure before the device loss; 5 live puddle planes in (b), 0 in the 21:11 run).
- Not the puddle planes alone ((a) survived with the planes and the wet world off).
- Not a fixed material or reload count (crashes at edit ~20, ~11 and at a later point; a standing car survived all 308).
- Not the reload pace (1 edit per 0.3 s still crashed).
- Not Part Wear, shadows or the Custom settings (separate checks).

## What helps today
Wet roads and walls off (default). Puddles and rain are unchanged.

## Hypotheses to try later (none proven)
1. **Wet asphalt feeding reflections at High.** The wet step sets roughness to `orig * (1 - f + f * rough)` and the base colour darker (core/wetworld.lua KINDS: asphalt rough 0.30, dark 0.60). At High, SSR / reflection probes read roughness; a very smooth dark asphalt that a car then drives over (moving reflections, wheel spray, headlights) might hang a shader. Test: keep the edits but never go below a roughness of, say, 0.5 of the original, or set only the colour factor, and drive.
2. **A vehicle rebuild (spawn, reset, replace) during the first seconds of the material reloads.** The 21:11 and 16:37 logs also show vehicle resets near the loss. A fix prepared and unmerged: branch worker-a-vehiclehold (gpugate VEHICLE_HOLD 2 s, bounded to 10 s). Probably not enough on its own: the stall began 2.7 s after the reset, so 2 s may be too short.
3. **The car's own materials in the plan** (332 vs 308): an edit to a vehicle's glass materials while it drives. Test: filter out materials whose file is empty or whose name matches a vehicle in the scene.
4. **A driver or driver-version issue** of the card (Windows logged nvlddmkm TDR events on this PC on other days).

## How to reproduce
SL branch worker-a-wettrace (63fb2a8) has a Developer row "Log each wet-world material edit": one "wet start" line before each edit, one "wet edit" line after. Turn it on, Wet roads and walls on, High graphics, force clear 5 s, then `sl_weather.debugForce('rain', 'heavy')`, reset a car onto a street and drive; the last "wet start" before the silence names the material. A standing car did not crash.
