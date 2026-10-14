# Street Legal Racing for BeamNG

A career in the spirit of *Street Legal Racing: Redline*, played on the Valo City map. You start on foot in the first garage with a few thousand and no car. The city's street racers are in your phone. Reputation from racing, worth more at night, takes you up through the three garages to the ROC.

Needs two other mods: the **Valo City** map (`slrr_valo_city`) and **Wrench Works** (the garage). BeamNG.drive 0.39.

## How it plays

- **Start**: Gameplay > Street Legal Racing > New career. Valo City at dusk, you on foot in Club Garage 1 with $3,500 and no car. Benny from the garage texts you where to begin.
- **Getting a car**: walk up to the junkyard's lot, the dealership or the scrap yard (the phone's Cab app takes you). Their cars stand on the display spot one at a time: left and right through the row, right-drag to look round it. Used cars come as tidy stock, tired stock, damaged, modified, or modified and broken; what is wrong with them is really wrong (parts missing, panels bent, parts swapped). Test drive it, buy it, then drive it home or have it towed.
- **Your cars**: kept between sessions with their setup, their dents and where you left them. Phone > My cars: tow one home, swap which one you drive (at the garage). Drive up to the junkyard or scrap yard in one and they make you an offer for it.
- **The garage**: Wrench Works, paid from career money.
- **Racing**, at night for the most reputation:
  - the map's night races, at their start lines;
  - **flash your high beams** at a racer cruising the streets (their name hangs over the car): if they rate you, it is a race to the other side of town for their usual stake;
  - **car meets**: some nights racers gather in a car park (you get a text); roll in and pick somebody: for money, high stakes or **pink slips**;
  - races **arranged by phone**, at a start line they choose.
- **Pink slips are real**: win and their car goes to your garage; lose and they drive off in yours.
- **The police**: caught, you pay a fine per offence (more mid-race, and the race is lost) and lose face; getting away earns a little.
- **Up the ladder**: reputation brings titles, new numbers in your phone, and the right to move to Club Garage 2 (1,500 rep, $25,000) and Club Garage 3 (3,000 rep, $75,000). From garage 3 at 6,000 rep: the **ROC**, three rounds against the best in town on the ROC island ($50,000 entry, $250,000 to the champion).

## What still needs the map

The junkyard, dealership, scrap yard and meet spots need coordinates from the Valo City map (see docs/integration.md). Until they are in, the cab and the lots only know the garages. The map's night races give reputation once they report results to the career (two lines, also in the doc).

## The phone

Press **K** (Options > Controls > Gameplay to change it). It is an Android-style phone: home screen with a dock, three-button navigation, notifications that drop in when a text arrives.

- **Contacts and Phone**: call a racer or dial their number. If they pick up, ask for a race for money, for high stakes (three times their usual), or for pink slips. Big names will not talk to you until you have a name yourself, and nobody races you without a car.
- **Messages**: the same by text, with quick replies; they write back after a moment.
- **Races**: what you have arranged, with directions to the start line on the road.
- **My cars**: where each one is, tow it home, take another one out. **Bank**: balance and statement. **Cab**: on foot, a cab takes you anywhere the career knows about. **Street cred**: title, reputation, garage, the ROC.

It is built as a web page inside the game's interface. A real Android system cannot run inside BeamNG.

## Install (development)

`tools/install.ps1` links `mod/` into BeamNG's `mods/unpacked` folder, so changes here are live after a Lua reload (Ctrl+L) and a UI reload (F5).

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
| `lua/ge/extensions/sl/phone.lua` | what the phone shows and what its buttons do |
| `lua/ge/extensions/sl/menuTile.lua` | the tile in Gameplay |
| `lua/ge/extensions/sl/core/*.lua` | the rules, no game calls: `progression`, `roster`, `market`, `cars`, `state`, `rng` |
| `ui/modModules/slPhone/slPhone.js` | the phone's screen |
| `docs/integration.md` | how it fits with the Valo City map and Wrench Works |
