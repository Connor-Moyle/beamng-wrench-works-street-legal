# Car theft: the contracts for the screens (9e) and the fence (19)

The game side is `sl/theft.lua`, the rules `sl/core/theft.lua` (Graph docs/CAR_THEFT.md). The part is off by default (Mods > Street Legal > Parts of the game > Car theft).

## The screens (9e): three mini-games, one UI module

**In:** `guihooks.trigger('slTheftGame', spec)` when a stage starts. `spec` = (`tools/theft_fixture.js` carries one of each):

```
{ vid = 1234, stage = 'lock' | 'box' | 'wires' | 'fob', stages = { 'lock', 'wires' },   -- the stages of this break-in, in order
  era = 'old' | 'mid' | 'modern', tool = 'slimjim' | 'bypass' | 'relay' | 'cloner' | nil,
  model = 'covet', name = 'Ibishu Covet DX', noise = 0.0,                                 -- the noise so far (0..1)
  difficulty = { era, prestige = bool, stages, seconds = 25, chance = 0.85,                -- seconds: the time for the WHOLE break-in; chance: the autoplay's roll
                 pins = 4, wires = 5, cut = 3,            -- lock: pins to lift; wires: how many run across, cut: how many to cut
                 windows = 2, sliders = 3 } }             -- fob: how often the pattern shows, the sliders to match
```

The screen for the stage: `lock` = the pins (or the slim jim drag when `tool == 'slimjim'`), `box` = fit the bypass box onto the harness plug (mid cars only), `wires` = cut the tagged wires, join battery to ignition, touch the starter and hold the crank, `fob` = capture the pattern in the window, then match the sliders (`tool == 'cloner'` skips the match). Escape = give up.

**Out:** the screen calls Lua once per stage: `sl_theft.gameResult(vid, stage, ok, noise)` with `ok` true/false and `noise` the noise the stage made (0..1: the rules' `NOISE` says a dropped pin 0.12, a wrong wire 0.2, a second crank 0.15, a fail 0.5). Escape or a timeout: `sl_theft.cancel()`. The game side then opens the next stage (another `slTheftGame`) or seats the player in the car; a fail sets the alarm off. While a break-in runs the noise meter and the timer are the screen's (the rules give the seconds); witnesses and the alarm are the game side's (the screen may show the toasts the game sends).

The phone's "Hot cars" list: `sl_theft.summary()` → `{ hot = { { index, name, model, era, value, plated, wanted, driving, sell, strip, plates, title } }, tools = { { id, title, uses } }, deliveries = n, breakingIn = bool }`.

Until the screens exist the Developer switch "Theft screens: autoplay" (`slTheftAutoplay`) resolves each stage by a roll against `difficulty.chance` after its share of the seconds, so the police side can be seen in the game first.

## The fence (19): a shop kind through the shops kit

A shop kind `fence` (`sl_shops.define('fence', { title = 'The Pier Lock-Up', goods = 'given', screen = 'catalogue', hours = 'night', ... })`) at the docks, found by a text once the player has 300 reputation and one bust. Its stock and services come from these calls (all answer `ok, text`; money moves inside them except the tools):

- **Tools:** `sl_theft.tools()` → `{ { id, title, price, uses, era, have, usesLeft } }`. The shop takes the money, then `sl_theft.buyTool(id)` puts the tool in the player's kit (a tool with `uses` runs down per break-in; one without lasts).
- **Hot cars:** `sl_theft.hotCars()` → the list above with the prices: `sell` (a third of the value hot, half plated), `strip` (40 %), `plates` ($800 + 5 %: clears the wanted record, the car can then be titled), `title` ($1,500 + 10 %: the car joins the fleet with a history line, after plates).
- `sl_theft.sell(index)`, `sl_theft.strip(index)`, `sl_theft.plates(index)`, `sl_theft.title(index)`. The car has to be standing at the shop (`driving` true, or within the shop's ring) for sell/strip/title: the shop checks that; the game side only acts on the record.

## Hooks and switches

- `onStreetLegalChanged` after every change. The wanted record of a hot car is `s.wanted` with `vid` (sl_justice recognises the vehicle by id).
- Switches: the part `slTheft` (off), `slTheftWitnesses` (on), `slTheftDeliveries` (on), `slTheftLockTraffic` (on: traffic cars are not enterable by the walker while the part is on), Developer `slTheftAutoplay` (off).
