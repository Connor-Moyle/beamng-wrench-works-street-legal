# How Street Legal Racing fits with the Valo City map and Wrench Works

Three mods, one game:

| Mod | Owns |
| --- | --- |
| Valo City (`slrr_valo_city`) | the map, its garages' positions, traffic, the night races (`slrrValoRaces`) |
| Wrench Works (`slrr_garage`) | the garage: working on the car, parts, catalog, shops |
| Street Legal Racing (`sl_*`) | the career: money, reputation, the climb through the garages, the phone, the racers, the car lots |

## One wallet

While a career runs, Street Legal Racing hands Wrench Works a money provider (`garageParts.setMoneyProvider`). From then on everything Wrench Works spends or pays, and everything that goes through `require('slrr/garageParts').changeMoney(amount, label)`, is career money. The night races already pay through `changeMoney`, so nothing more is needed there.

## What the night races should tell the career (two small additions to `slrrValoRaces.lua`)

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

and expects the race to start against that opponent without the usual menu. The class can be mapped onto the existing candidate list by power-to-weight: beater the slowest sixth, super the fastest. Until `startChallenge` exists, the career tells the player to pick the opponent from the race menu.

**3. Filling the start lines with the career's racers** (optional, while a career runs). In `makeOffers`, before inventing opponents:

```lua
local crowd = sl_career and sl_career.racersForRace and sl_career.racersForRace(current.id, #TIERS)
-- nil when no career is running; otherwise up to 5 of { racerId, name, class, skill, bet, pinkOK, tier }
```

Use their names, stakes and classes (map the class to a car as in 2), and hand `racerId` back in the finish hook (`racerId = o.racerId`). Then the people at the start lines are the same people who are in the player's phone, and who know them.

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

The three garages need no entry: they come from Wrench Works' sites (`slrrGarage1`..`3`). The ROC is raced from the level's `spawn_roc` object to the far end of the ROC island's roads.

In the game, standing at the spot: `sl_career.addPlaceHere("junkyard", "Valo Junkyard")` writes the same thing to the player's own `settings/street_legal/places.json`.
