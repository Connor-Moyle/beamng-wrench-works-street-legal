# Maps app (landscape phone on the HUD): design note

Status: plan and a drawing prototype only. Nothing here is wired into the game yet. Mock: `tools/mapsmock.js` renders it with the shipped drawing code (`mod/ui/modules/apps/slMaps/mapdraw.js`).

## What the player gets
- A HUD app "Maps" (ESC > apps layout editor: place and resize like any app): our phone frame in landscape with a live map.
- Press K: the phone turns 90 degrees and slides to the right edge as the normal portrait phone (about 400 ms, eased). Close reverses it.
- The map is our own drawing in a light road-map style. No third-party name, logo or icon.

## Pieces
1. **App shell** `mod/ui/modules/apps/slMaps/{app.json,app.js}`: a legacy angular app, like Wrench Works' `slrrGarage` (the same mechanism, so the game's app editor places and resizes it). `interactive: "no"` at first (the HUD map is for looking; taps come later). Min size about 300x160, any aspect.
2. **Drawing** `mapdraw.js` (done, offline tested by the mock): ground, parks and water areas, roads in four classes (casing then fill, so crossings join), route line, labels, pins, location dot with a heading cone. `rot` gives north-up or heading-up.
3. **Data feed** (new Lua `sl/mapsfeed.lua`):
   - Road geometry from `map.getMap()` nodes and links, built once per level and cut into 256 m tiles of simplified polylines. Class from the link's speed limit or node radius (to be checked on the real data: not yet looked at).
   - Sent to the UI per tile on demand (the app asks for the tiles it needs), never the whole map in one event.
   - The player pose (x, y, heading) at 10 Hz; the route from `core_groundMarkers` (already in the phone's map code); the pins from `allPlaces` by kind.
   - Parks and water: the road graph has none. Plan: water and park polygons only if the level or our places data provides them; otherwise none (the prototype's green and blue are decoration). Honest limit.
4. **Cache and cost**: each tile is drawn once to an offscreen canvas per zoom step and then blitted; the live layer (route, pins, player) redraws at 10 fps or less. Target: under 2 ms per frame in the UI, no Lua cost beyond the tile builds (spread across frames, the same 2 ms rule as the puddles).
5. **K transition**: the phone is a global UI module (`slPhone.js`, an overlay), the Maps app lives in the app layer. The overlay reads the app's screen rect (the app reports it on layout and resize), starts the portrait phone as a copy of that rect rotated 90 degrees and animates a CSS transform to its resting place at the right edge. Reduced motion: `prefers-reduced-motion` skips the animation (the game does not offer its own flag that I know of; to check).
6. **Settings** (Mods menu, Street Legal tab "Maps"): show the HUD phone, map style (light, dark), heading-up, zoom, opacity. Registered the same way as the other Street Legal rows.

## Build order
1. Data feed and the app with a plain map (north-up, zoom, player, route). 80 proves it in the real UI.
2. Pins, labels, heading-up, settings.
3. The K transition last (it touches the phone, the riskiest part).

## Risks and unknowns (not checked yet)
- What `map.getMap()` gives per link (speed limit, drivability, radius) decides the road classes; the prototype assumes four.
- Whether the app can report its rect to the overlay in the game's UI browser (expected yes: `getBoundingClientRect` on the directive element).
- Road count on the big map: tiles and simplification are there to keep the event sizes small; sizes to be measured.
- Park and water shapes may not exist; the style works without them.
