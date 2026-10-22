# Car theft: the contracts for the screens (9e), the fence and black market (19), the fuel siphoning (ba)

The game side is `sl/theft.lua`, the rules `sl/core/theft.lua` (Graph docs/CAR_THEFT.md). The part is off by default (Mods > Street Legal > Parts of the game > Car theft). Every number of the rules is a row on the Mods page "Car theft" (`scope = 'gameplay'` for the presets, Easy and Hardcore values where they differ); the defaults below are the design's.

## The screens (9e): three mini-games, one UI module (built: ui/modModules/slTheft)

**In:** `guihooks.trigger('slTheftGame', spec)` when a stage starts. `spec` = (`tools/theft_fixture.js` carries one of each):

```
{ vid = 1234, stage = 'lock' | 'box' | 'wires' | 'fob', stages = { 'lock', 'wires' },   -- the stages of this break-in, in order
  era = 'old' | 'mid' | 'modern', tool = 'slimjim' | 'bypass' | 'relay' | 'cloner' | nil,
  model = 'covet', name = 'Ibishu Covet DX', noise = 0.0,                                 -- the noise so far (0..1)
  difficulty = { era, prestige = bool, stages, seconds = 25, chance = 0.85,                -- seconds: the time for the WHOLE break-in; chance: the autoplay's roll
                 pins = 4, wires = 5, cut = 3,            -- lock: pins to lift; wires: how many run across, cut: how many to cut
                 windows = 2, sliders = 3 } }             -- fob: how often the pattern shows, the sliders to match
```

**Out:** the screen calls Lua once per stage: `sl_theft.gameResult(vid, stage, ok, noise)` with `ok` true/false and `noise` the noise the stage made (0..1: a dropped pin `NOISE_PIN` 0.12, a wrong wire `NOISE_WIRE` 0.2, a second crank 0.15, a fail 0.5). Escape, give up or a timeout: `sl_theft.cancel()`. The game side then opens the next stage (another `slTheftGame`) or seats the player in the car; a fail sets the alarm off. **`guihooks.trigger('slTheftEnd', { vid })`** goes out whenever the break-in ends on the game side (stolen, failed, cancelled, the career stopped): the screen closes on it.

**The HUD mark:** `guihooks.trigger('slTheftTracked', { on = true | false, name })` when the car the player drives is tracked by the police (and when the tracker is out): a "TRACKED" mark on the HUD; `sl_theft.summary().tracked` says the same for a redraw.

**The phone's "Hot cars" list:** `sl_theft.summary()` → `{ hot = { { index, name, model, era, value, plated, resprayed, legal, tracked, plate, wanted, driving, present, sell, strip, plates, title, stripTracker } }, tools = { { id, title, uses } }, deliveries = n, breakingIn = bool, tracked = bool, fenceKnown = bool, busts = n }`. Buttons the list may offer on the car the player sits in: `sl_theft.pullTracker()` (the timed search, the car standing; the finder tool makes it 18 s instead of 45) and `sl_theft.jam()` (the jammer tool: silent 120 s). Both answer `ok, text`.

Until the screens are merged the Developer switch "Theft screens: autoplay" (`slTheftAutoplay`) resolves each stage by a roll against `difficulty.chance` after its share of the seconds.

Texts: 9e's module keeps its own TEXT table for the screens (fine: the screens are a UI module like the phone's pages); the toasts and the radio lines come from `sl/core/strings` (`theft.*`).

## The fence and the black market (19): shop kinds through the shops kit

19's six questions, answered. All the calls answer `ok, text`; **money moves inside my calls** unless the shop passes `paid = true` (the kit charged the service line already). The shop decides where and when (the Pier Lock-Up at the docks, night only); the marker shows when `sl_theft.fenceKnown()` (I flip `s.theft.fenceKnown` at 300 reputation after the first bust and send Benny's text; `sl_theft.debugFence()` for the tester).

1. **Tools:** my core owns the table (`sl/core/theft.TOOLS`: id, title, price, uses, era, kind). `sl_theft.tools()` → `{ { id, title, price, uses, era, kind, have, usesLeft } }` with the menu's price and uses factors applied; the shop takes the money, then `sl_theft.giveTool(id)` (uses stack; `buyTool` is the same call) and `sl_theft.toolCount(id)` (uses left; 1 for a tool without uses; 0 when not held). When the inventory lands (19's INVENTORY.md) the tools become `tool` items with `uses` and these two calls move to it; the fields stay (id, title, price, uses, era, kind).
2. **Plates:** `sl_theft.plateOf(carId)` (a fleet car's plate text) and `sl_theft.newPlate(carId, paid)`: $300 (`PLATE_LEGAL`), a new seeded text, applied to the car, and a normal wanted poster is cleared (P9: a repaint or a plate change). For a **stolen** car it is `sl_theft.plates(index, paid)`: $700 (`PLATE_STOLEN`), the car has to be present. The text is mine (`core/theft.plateText(seed)`: three letters, a space, three digits). The legal counter: a service line on the accessories shop is enough (no new place; the accessories shop's $60 text-only plate goes: a plate is always $300 now).
3. **The black market:** my core gives the day's list: `sl_theft.blackMarket()` → `{ { index, model, name, value, era, price, sold } }` (three cars from the game's models, 45 % of the value, the same all day). `sl_theft.buyHot(index, paid)` takes the money, spawns the car eight metres from the player and makes it a hot record: **wanted at once** and maybe tracked (the roll is in the list). No `addStolen` needed.
4. **Services on a hot car** (`index` from `hotCars()`/`current()`): `sell(index)`, `strip(index)` (pay out inside; the car is deleted), `plates(index, paid)`, `stripTracker(index, paid)` ($350), `title(index, paid)` (15 % of the value, at least $400; needs the car legal = resprayed AND plated; registers the car with the fleet with its plate and a history line). The **respray** is the paint shop's existing service: call it as today; my `onWrenchWorksPainted(vid)` marks the record resprayed. A bundled line "Respray and plates" = the paint service + `plates(index, true)`.
5. **The car under the counter:** `sl_theft.current()` → the hot record of the car the player sits in (the row above, with `index`), or nil.
6. **Opening:** `sl_theft.fenceKnown()`.

Prices (checked with `economy_sim --seeds 5`): the fence's hot cut is **a fifth** (a third paid $331 a minute, twice any job; a fifth pays $188 against a dealer delivery's $156 with the bust risk on top); a title 15 % (min $400); black market 45 %: all-in with the respray ($800), plates ($700) and the title, a $6k car costs $5,100, a $30k car $19,500, a $120k car $73,500 against the dealer.

## Fuel siphoning (ba): the calls

- `sl_theft.fairGame(vid)` → `ok, reason` (`'own'`: the player's, a fleet, lot, meet or police car, a hot car of ours; `'running'`: moving). Only with the Car theft part on (the gate answers nil otherwise: treat nil as no).
- `sl_theft.exposure(vid, noise)` → `{ witness, alarm }`: applies the witness rule (people about and the noise past `WITNESS_AT`, half by day: a heat level if "Witnesses raise the heat" is on) and the alarm rule (noise at `ALARM_AT`: the horn and hazards on that car, a heat level, a patrol within 300 m comes). The pure rule without the effects: `require('sl/core/theft').exposure(noise, peopleAbout, isDay)`.

## Hooks and switches

- `onStreetLegalChanged` after every change. The wanted record of a hot car is `s.wanted` with `vid` and `stolen = true` (sl_justice recognises the vehicle by id). A hot car stops being wanted only resprayed AND plated.
- Vehicle ids never survive a restart: on career start the hot cars are rebuilt where they last stood (`rec.pos`), the ids forgotten; every delete or register checks the vehicle is the record's model and nobody's fleet car.
- Switches: the part `slTheft` (off), `slTheftWitnesses` (on), `slTheftDeliveries` (on), `slTheftLockTraffic` (on: a stopped traffic car in reach gets `playerUsable = false`, per car), `slTheftPlates` (on: the plate rule), Developer `slTheftAutoplay` (off). The numbers: the Mods page "Car theft" (`sl/balance` MAP: `slTheft*` rows).
