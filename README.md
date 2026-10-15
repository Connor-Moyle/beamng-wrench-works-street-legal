# Street Legal Racing for BeamNG

A career in the spirit of *Street Legal Racing: Redline*, played on the Valo City map. You start on foot in the first garage with a few thousand and no car. The city's street racers are in your phone. Reputation from racing, worth more at night, takes you up through the three garages to the ROC.

Needs two other mods: the **Valo City** map (`slrr_valo_city`) and **Wrench Works** (the garage). BeamNG.drive 0.39.

## How it plays

- **Start**: the main menu's **Career** button asks which career: BeamNG's own, or **Street Legal Racing** (Continue or New career). Also under Gameplay > Street Legal Racing. Valo City at dusk, you on foot in Club Garage 1 with $3,500 and no car. Benny from the garage texts you where to begin.
- **Getting a car**: walk up to the junkyard's lot, the dealership or the scrap yard (the phone's Cab app takes you). Two to six cars stand in a row under floodlights (a different count and choice each day); the camera glides from one to the next as you go left and right, right-drag to look round the one on show. Used cars come as tidy stock, tired stock, damaged, modified, or modified and broken; what is wrong with them is really wrong (parts missing, panels bent, parts swapped). Test drive it, buy it, then drive it home or have it towed.
- **Your cars**: kept between sessions with their setup, their dents and where you left them. Phone > My cars: tow one home, swap which one you drive (at the garage). Drive up to the junkyard or scrap yard in one and they make you an offer for it.
- **The garage**: Wrench Works, paid from career money.
- **Racing**, at night for the most reputation:
  - the map's night races, at their start lines;
  - **flash your high beams** at a racer cruising the streets (their name hangs over the car): if they rate you, it is a race to the other side of town for their usual stake;
  - **car meets**: some nights racers gather in a car park (you get a text); roll in and pick somebody: for money, high stakes or **pink slips**;
  - races **arranged by phone**, at a start line they choose, or a **drag race** down the test track's quarter mile or mile. The racer turns up in their own car.
- **Every racer has their own car**: a stock car of their class built up by tier, from a stock beater to Stage 3 (turbo, brakes, aero, suspension), with a nickname and a paint job. At the ROC they bring the track version: race parts, stripped interior. The dealership now and then has a **Track special**.
- **Race starts and flares**: start lines with a chequered line and posts; when a race goes green, orange road flares (some throwing a flickering light) line both edges of the whole route, or every checkpoint of the ROC circuit.
- **Pink slips are special**: only a few racers put their car up on any one night (Benny texts you at dusk who), and only they offer it. They are real: win and their car goes to your garage; lose and they drive off in yours and you walk home.
- **The police**: caught, you pay a fine per offence (more mid-race, and the race is lost) and lose face; getting away earns a little.
- **Up the ladder**: reputation brings titles, new numbers in your phone, and the right to move to Club Garage 2 (1,500 rep, $25,000) and Club Garage 3 (3,000 rep, $75,000). From garage 3 at 6,000 rep: the **ROC**, three rounds against the best in town on the ROC island ($50,000 entry, $250,000 to the champion).

## The map

The career is played on the Valo City map mod, which brings the places (garages, junkyard, dealership, scrap yard, meet spots, the lots' display spots), the night and drag races and the ROC track; docs/integration.md has the contract between the two.

## The phone

Press **K** (Options > Controls > Gameplay to change it). It is an Android-style phone: home screen with a dock, three-button navigation, notifications that drop in when a text arrives.

- **Contacts and Phone**: call a racer or dial their number. If they pick up, ask for a race for money, for high stakes (three times their usual), or for pink slips. Big names will not talk to you until you have a name yourself, and nobody races you without a car.
- **Messages**: the same by text, with quick replies; they write back after a moment.
- **Races**: what you have arranged, with directions to the start line on the road.
- **My cars**: where each one is, tow it home, take another one out. **Bank**: balance and statement. **Cab**: on foot, a cab takes you anywhere the career knows about. **Street cred**: title, reputation, garage, the ROC.

It is built as a web page inside the game's interface. A real Android system cannot run inside BeamNG.

## Install (development)

`tools/install.ps1` links `mod/` into BeamNG's `mods/unpacked` folder, so changes here are live after a Lua reload (Ctrl+L) and a UI reload (F5).

## Debug cars

The racers' custom cars are kept out of the vehicle selector. For testing, from the console (`~`, GE Lua):

```
sl_debugCars.list()                 -- the lineup: street builds Stage 1-3 from every class, track cars from the fastest
sl_debugCars.spawn(12)              -- build number 12 in front of you and get in
sl_debugCars.spawn("night fury")    -- or by name
```

Nothing is written to disk; a car is built when it is asked for.

## Tests

```
npm i fengari jsdom
node tools/luatest.js     # the rules: money, reputation, garages, racers, car market, the save
node tools/phonetest.js   # the phone, in a simulated page (--html <file> writes a preview of its screens)
```

## Source

| File | Job |
| --- | --- |
| `lua/ge/extensions/sl/career.lua` | the career: start/continue, save, clock, wallet, places, arranged races, police, moving garage |
| `lua/ge/extensions/sl/fleet.lua` | the player's cars: kept, restored, towed, swapped, sold, lost |
| `lua/ge/extensions/sl/lot.lua` | the junkyard, dealership and scrap yard: browse, test drive, buy, sell |
| `lua/ge/extensions/sl/streets.lua` | cruising racers, flash to race, car meets, the race runner, pink slips, the ROC |
| `lua/ge/extensions/sl/carBuilder.lua` | stock cars, cars built as an offer says, saving and restoring a car |
| `lua/ge/extensions/sl/markers.lua` | start lines, road flares along a race |
| `lua/ge/extensions/sl/debugCars.lua` | the custom cars for testing, from the console (not in the vehicle selector) |
| `lua/ge/extensions/sl/phone.lua` | what the phone shows and what its buttons do |
| `lua/ge/extensions/sl/menuTile.lua` | the tile in Gameplay |
| `lua/ge/extensions/sl/core/*.lua` | the rules, no game calls: `progression`, `roster`, `market`, `cars`, `builds`, `state`, `rng` |
| `ui/modModules/slPhone/slPhone.js` | the phone's screen |
| `docs/integration.md` | how it fits with the Valo City map and Wrench Works |
