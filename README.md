# Street Legal Racing for BeamNG

A career in the spirit of *Street Legal Racing: Redline*, played on the Valo City map. You start on foot in the first garage with a few thousand and no car. The city's street racers are in your phone. Reputation from racing, worth more at night, takes you up through the three garages to the ROC.

Needs two other mods: the **Valo City** map (`slrr_valo_city`) and **Wrench Works** (the garage). BeamNG.drive 0.39.

## Where it stands

Version 0.1: the frame of the game.

| Works | Next |
| --- | --- |
| Gameplay > Street Legal Racing: Continue / New career | Car lots: scroll through the cars like SLRR, look round them, test drive, buy |
| New career: Valo City at dusk, on foot in Club Garage 1, no car | Junkyard, dealership and scrap yard (the offers are already worked out: `sl/core/market.lua`) |
| Career save: money, reputation, title, garage level, day, stats | Owned cars kept between sessions, towing home |
| One wallet: the garage, the shops and the night races all use career money | Street racers driving round town; flash your high beams to race them across the map |
| Reputation from races (needs one hook in the night races, see docs/integration.md) | Random car meets |
| 36 street racers per career, each with a number, a car class, a stake and a way of talking | Moving garages, the ROC |
| The phone (K): contacts, calls, texts, arranged races with directions, bank, cab, street cred | Pink-slip results changing which cars you own |

## The phone

Press **K** (Options > Controls > Gameplay to change it). It is an Android-style phone: home screen with a dock, three-button navigation, notifications that drop in when a text arrives.

- **Contacts and Phone**: call a racer or dial their number. If they pick up, ask for a race for money, for high stakes (three times their usual), or for pink slips. Big names will not talk to you until you have a name yourself, and nobody races you without a car.
- **Messages**: the same by text, with quick replies; they write back after a moment.
- **Races**: what you have arranged, with directions to the start line on the road.
- **Bank**: balance and statement. **Cab**: on foot, a cab takes you anywhere the career knows about. **Street cred**: title, reputation, garage, the ROC.

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
| `lua/ge/extensions/sl/career.lua` | the career: start/continue, save, clock, wallet, places, arranged races |
| `lua/ge/extensions/sl/phone.lua` | what the phone shows and what its buttons do |
| `lua/ge/extensions/sl/menuTile.lua` | the tile in Gameplay |
| `lua/ge/extensions/sl/core/*.lua` | the rules, no game calls: `progression`, `roster`, `market`, `state`, `rng` |
| `ui/modModules/slPhone/slPhone.js` | the phone's screen |
| `docs/integration.md` | how it fits with the Valo City map and Wrench Works |
