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
| vehiclehold 1726fb8 + trace, car excluded from the plan | High/Custom, wet tarmac on | on, trace on, 10 puddles | reset onto a street, then stood still (engine start failed) | crashed 96 s into the rain, 5.2 s after edit #262 of 327; the first edit came 2.1 s after the reset (the 2 s hold worked) |
| wetrun 08a096f (empty-file fix + trace), car driving | High/Custom, wet tarmac on | on, trace on, 10 puddles | reset onto a street, engine running, driven 11 m/s | crashed 54 s into the rain, 5.0 s after edit #132 of 323 (a terrain rock imposter); plan 323 with glass 26 |

## The 11-edit crash (crash_2026-10-21_2251_highrain_wettrace_63fb2a8_driving.log in the graph repo's crashlogs)
- Edits #1-#11 were all asphalt, the last at 211.88 s; no "wet start" without its edit afterwards, so no edit was running at the hang. The next Lua log line is the device loss at 217.14 s: a 5.3 s silence.
- The car was rebuilt just before: slrrDrivers logged the autobello's wheel at 209.16 s, "parts that fell off" at 209.72 s; the first edit was at 209.59 s. So a vehicle reset/respawn happened about 0.4 s before the first edit and 2.7 s before the stall (the reset is in the first seconds of the edits, not at the moment of the stall).
- The plan had 332 materials (glass 35) where the standing runs had 308 (glass 11): the car's materials seem to enter the plan when the car exists, although `classify` skips files under /vehicles/. Unchecked: which 24 glass materials these were.
- One misclassification seen in the trace: a tree imposter material (`imposter_mat_levels_west_coast_usa_art_shapes_trees_trees_conifer_redwood_broad.dae`) counts as asphalt.

## The extra glass (found, 2026-10-21)
Every High run that crashed had the car in the world when the plan was read; the one run that finished all 308 edits (standing, trace) had a plan of 308 materials with 11 glass. A Low, no-rain check (80) named the extras: with the autobello spawned the plan grew from 308 to 328 (glass 11 -> 31). The 20 extra glass materials are vehicle-side materials registered when a car is loaded (autobello_*glass, bx_*glass, hopper_*glass, fullsize_*glass: lamp glass of other models that come with the car's parts), all with an EMPTY file path (`getFilename()` gives ''), and only 5 of them are in this car's `getMaterialNames()` (hence the exclusion by name in worker-a-vehiclehold missed 15). They stay registered after the car is despawned (328 stays). The level's own 11 glass materials all have level/art file paths.
Fix, in master since 6aadb98: `plan()` skips every material whose file is reported as '' (vehicle-side). It was tried in a High driving run (wetrun 08a096f) and the game still lost the device: the plan read 323 materials with glass 26, so the fix removed only 5 of the 20 extra glass materials. Open question: what file path do the other 15 report? 80's console check printed `getFilename()` as '' for all 20, but its script turned a nil result into '' (`okF and f or ''`), while the plan sees `nil` as "file cannot be read" and still classifies by name. The likely answer is that 15 of them return nil (not ''), which a further `file or ''` in `materials()` (wetworld.lua) would catch; this was NOT tried, and no High run was made with it.

## Closing (2026-10-22)
Five High runs with the wet world on lost the device (the 21:11 run, (b), the driving trace run, the vehiclehold run and the wetrun run), 52-96 s into forced heavy rain and about 5 s after an edit of an asphalt, terrain, rock-imposter or foliage material; the one standing run finished all 308 edits, and the run with the wet world off survived 628 s. The wet world at High is parked: Wet roads and walls is off by default (0.6.1) with a warning in its row. The branches kept for later: worker-a-vehiclehold (hold after a vehicle change, car-name exclusion), and the optional edit trace (slWetTrace, in master).

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

## Closing finding (2026-10-23): terrain layers only survived at High
A run of the branch wet-terrain-only-ba (the wet world changes only the terrain layers: a texture swap, no Material reload; the 300-odd material edits only run when the options key slWetMaterials is true): Connor's High/Custom settings, QA career on west_coast_usa, Autobello bought at the junkyard, Wet roads and walls ON, Wet tarmac ON, forced heavy rain, 6 legs of reset + engine start + 16 s cruise (up to 11.6 m/s) on the street.
- **No crash and no hang in 366 s of heavy rain** (every earlier run with the material edits on lost the device 52 to 96 s into the rain). No `device is gone` / 0x887a line, no error from sl_wetworld or Car Surface FX. The profile stayed `step 6/6, terrain tier 2, 0 materials planned, 0 edits`.
- VRAM (Engine.Render.getVRAMUsage) went 4.12 GB to 4.31 GB in the first minute and then stayed flat.
- Car Surface FX asked for 25 material reloads in the whole run (the car and driver paint rung walk, at the start of the rain), none afterwards, and no glass canvas; slotStats() was identical at 11 samples.
- Frame time was not recorded in this run.

What this settles:
- The reload-leak hypothesis (every material reload takes a slot of the 8192-slot material cbv array) is **disproved**: 900 reloads of one static material (concrete_plain, one per 0.1 s, Low, no rain) never produced the `bindless| material cbv array exhausted` line and never hung (frame costs flat).
- The `bindless| material cbv array exhausted (8192 slots), using raw material loads for overflow blocks` warning is a **separate event on the car/career spawn side**: in the High terrain run it came once at 368.9 s, 50 s before the rain started, right after the junkyard lot visit and the car purchase, and nothing bad followed. It is not what lost the device in the older runs (it was only in 3 of the 5 crash logs).
- What is still not proven: that the material edits were the whole cause of the old crashes (the run changes one thing, the 300-odd reloads, and the crash is gone), and that terrain-only is safe over longer or repeated runs (one run, 366 s). Walls, roofs, pavements and foliage no longer get wet; any cheap look for them must not reload materials.
- Next: a second High run on the merged build; if it is clean too, "Wet roads and walls" may go back to on by default (62's call).

