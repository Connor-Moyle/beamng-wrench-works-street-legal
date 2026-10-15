# How Wrench Works: Street Legal fits with the Valo City map and Wrench Works

The BeamNG Wrench Works family, one game:

| Mod | Owns |
| --- | --- |
| Wrench Works: Valo City (`slrr_valo_city`) | the map, its garages' positions, traffic, the races (`slrrValoRaces`), the race venues, racing lines, the navigator map |
| BeamNG Wrench Works (`slrr_garage`) | the garage: working on the car, parts, catalog, shops, the Services drawer |
| Wrench Works: Street Legal (`sl_*`) | the career: money, reputation, the climb through the garages, the phone, the racers, the car lots |
| Wrench Works: Drivers & Pedestrians (`slrrDrivers`, `slrrPedestrians`) | SLRR's drivers in the cars, pedestrians on the sidewalks (optional) |

## One wallet

While a career runs, Wrench Works: Street Legal hands Wrench Works a money provider (`garageParts.setMoneyProvider`). From then on everything Wrench Works spends or pays, and everything that goes through `require('slrr/garageParts').changeMoney(amount, label)`, is career money. The night races already pay through `changeMoney`, so nothing more is needed there.

## Before missions: what the night races tell the career (`slrrValoRaces.lua`)

**1. When a race is over**, at the end of `finishRace(playerWon)`:

```lua
extensions.hook('onSlrrRaceFinished', {
  won = playerWon,              -- the player won
  stake = stake,                -- 'money' or 'pink'
  bet = o.bet,                  -- what was on it (0 for pink slips)
  raceId = current.id,          -- the race's id from races.json
  opponent = o.name,
})
```

The career turns that into reputation (more at night, more against better-known racers), keeps the racer's record against the player, and gives out new phone numbers as the player becomes known. The money has already moved through the shared wallet, so the career does not touch it.

**2. A race arranged on the phone**: when the player arrives at a race start where they have a date, the career calls (if it exists)

```lua
slrrValoRaces.startChallenge(raceId, {
  name = 'Mick "Clutch" Santana',  -- shown as the opponent
  racerId = 'r07',                 -- the career's id for them (hand it back as opponent in the hook above, if convenient)
  class = 'muscle',                -- beater | compact | muscle | tuner | sport | super: what kind of car they bring
  skill = 0.62,                    -- 0..1: how hard they drive (aggression)
  stake = 'money',                 -- or 'pink'
  bet = 1200,
})
```

and expects the race to start against that opponent without the usual menu. The career keeps this in step every 2 seconds: it hands over its newest arranged race that can be raced now (a racer who only comes out at night is held back in daylight), or nil when there is none. The class can be mapped onto the existing candidate list by power-to-weight: beater the slowest sixth, super the fastest. Until `startChallenge` exists, the career tells the player to pick the opponent from the race menu.

**3. Filling the start lines with the career's racers** (optional, while a career runs). In `makeOffers`, before inventing opponents:

```lua
local crowd = sl_career and sl_career.racersForRace and sl_career.racersForRace(current.id, #TIERS)
-- nil when no career is running; otherwise up to 5 of { racerId, name, class, skill, bet, pinkOK, tier }
```

Use their names, stakes and classes (map the class to a car as in 2), and hand `racerId` back in the finish hook (`racerId = o.racerId`). Then the people at the start lines are the same people who are in the player's phone, and who know them.

## Races as BeamNG missions (current)

When the map has them, the career uses `slrrValoRaces.listRaces()` and `slrrValoRaces.launch(missionId, offer)`; otherwise the older `startChallenge` path below.

- `listRaces()` returns `{ id, missionId, name, kind = 'night'|'drag'|'circuit'|'venue', ref, laps, start = {x,y,z}, distance }`. Night races and drags are the career's start lines (phone dates, flash-to-race, meets); circuits and venues (not the ROC) are the garage's Tracks list.
- An arranged race: the racer's own car is built and frozen as the player drives towards the start; stopping at the start (within 8 m, under 1.5 m/s) calls `launch(missionId, { name, racerId, class, skill, aggression, stake, bet, car, vehicleId, laps })`. The map moves that car onto the grid and drives it.
- Started from the map's own marker with no offer, while a career runs: the map fires `onSlrrRaceOffer(missionId, req)`; the career fills `req.offer` when the player has a date on that race, otherwise it is raced for nothing.
- `onSlrrRaceStarted(missionId, raceId)` at the green light raises police heat; `onSlrrRaceFinished(result)` carries the fields below plus `missionId, place, time, abandoned, opponentVid` (an abandoned race counts as lost).
- The garage's Tracks list switches to the map's circuit missions only when `slrrValoRaces.circuitOpponents` is true (they put our racer's car on the grid). Until then the career runs those venues itself from `/levels/<level>/multibot_tracks.json` (`label, type, start, checkpoints, route`; a venue's checkpoints leave out the start line) with the opponent on `/levels/<level>/racelines/slrr_mb_<venue>.json` (`points = {{x, y, z, speed}}`, also `racelines/roc.json` for the ROC).

## The navigator map

The dashboard's road map uses `/street_legal/minimap/<name>.json` when `<name>` is part of the level id: `{ image, x0, y0, x1, y1 }` (world x/y at the image's top-left and bottom-right), or `tiles = [ ...same fields... ]` drawn in order (the whole level first, the city on top). Without it the map is drawn from the navgraph.

## The driver mod

With Wrench Works: Drivers & Pedestrians: each career car keeps the driver chosen in the garage (`slrrDrivers.setDriver`), racers get `slrr_opponent1/2`, patrols `slrr_police`, cars for sale none. Wrench Works' "Driver" setting calls `slrrDrivers.setDisplayMode('hidden'|'hideFirstPerson'|'full'|'still')` when it differs from `getDisplayMode()`.

## Places for the career

The career's cab and the car lots need to know where things are. Any mod can add them in `/street_legal/places/<anything>.json`:

```json
{ "slrr_valo_city": { "places": [
  { "id": "junkyard", "kind": "junkyard", "name": "Valo Junkyard", "pos": [x, y, z], "dir": [x, y] },
  { "id": "dealer", "kind": "dealer", "name": "City Motors", "pos": [x, y, z], "dir": [x, y] },
  { "id": "scrapyard", "kind": "scrapyard", "name": "Scrap & Salvage", "pos": [x, y, z], "dir": [x, y] }
] } }
```

`pos` is where a cab drops you (on the pavement at the gate), `dir` the way you face on arrival. Walking up to `pos` of a junkyard, dealer or scrap yard opens its lot. `display` / `displayDir` is where the car for sale stands, with room for the camera to go round it (if left out: 7 m in front of `pos`).

Places of kind `meet` are where racers gather on some nights: a car park or a wide lot, with room for half a dozen cars in a ring around `pos`.

**The ROC** is run from races.json key `roc` ({ name, looped, checkpoints = [ { pos, dir, halfWidth } ] }, the first checkpoint being start/finish): two laps from a grid behind the start line, the opponent on a timed line worked out from the checkpoints. Without that key the ROC falls back to a run from `spawn_roc` to the far end of the island's roads.

**Pink slips in the map's races** while a career runs: on a win the player sits in the opponent's car when the hook arrives, and the career registers it as theirs; on a loss the career drops the car the player raced and puts them on foot (it deletes the replacement car the race gives).

The three garages need no entry: they come from Wrench Works' sites (`slrrGarage1`..`3`). The ROC is raced from the level's `spawn_roc` object to the far end of the ROC island's roads.

In the game, standing at the spot: `sl_career.addPlaceHere("junkyard", "Valo Junkyard")` writes the same thing to the player's own `settings/street_legal/places.json`.
