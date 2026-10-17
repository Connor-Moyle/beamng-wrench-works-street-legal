# Wrench Works: Street Legal

A street-racing career for BeamNG.drive on **West Coast USA**, in the spirit of *Street Legal Racing: Redline*. You start on foot with a few thousand dollars and no car. Buy something that runs, fix it up in the garage, earn money by day, race the streets by night, keep ahead of the police and build a name: from a beater to the best in town.

Part of the **Wrench Works** family. BeamNG.drive 0.39.

## What you need

- BeamNG.drive 0.39 and its map **West Coast USA** (it comes with the game).
- **Wrench Works: Garage 1.7.0** (`wrench_works.zip`): the garage this career works in. Required.
- **Wrench Works: Drivers & Pedestrians 1.4.0** (`slrr_drivers.zip`): a driver in every car and people on the sidewalks. Optional, recommended.
- **Wrench Works: Driver Injuries** (`slrr_injury.zip`, an add-on to Drivers): optional.

The download **Wrench Works Street Legal - West Coast** (`wrench_works_street_legal_west_coast.zip`) holds all four mods with the versions each one needs of the others, and a checksum list. You can also install the single zips.

## Install

1. Unzip the download and copy the `.zip` files inside (not the other files) into your BeamNG mods folder: `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods`. Do not unzip those zips.
2. Start BeamNG.drive. On the main menu, **Career** asks which career: BeamNG's own or **Wrench Works: Street Legal**. Pick it, then **New career** and **West Coast USA**.
3. The mods check each other's versions when a level loads and tell you if one is too old or missing.

## Your first hour

1. You wake up on foot in your garage. **Benny** texts you: open **Messages** on the phone (key **K**). The tutorial takes you through buying a car.
2. Get a car: the **Cab** app takes you to a dealer or the junkyard. A few cars stand in a row; look at them, test drive one, buy it. The cheapest car on the used lot is one you can afford.
3. Drive it to your garage. Walk or drive into the door: the car goes onto the lift. Click a part to take it off, click a part on the shelf to fit it. The **Catalog** sells new parts; hover one to see what it does.
4. Earn money by day: the **Jobs** app. Spend it on parts (**Part market**) or a better car (**Car market**).
5. When you are ready, open **Wait** and **Start the night**. Racers are in your **Contacts**: ask for a race for money or pink slips.

The whole guide is in the game: the phone's **Help** app and the **Help** icon on every laptop. It is also in `docs/PLAYER_GUIDE.md`, made from the same words.

## Dealers and buying

Every dealership, junkyard and scrap yard on the map is a place to buy or sell: walk (or drive) to its marker and choose **Look at the cars**. The cars stand in the lot's painted bays; each has a card with **Test drive**, **Buy** and **Show full car report** (every part by section with its condition, dents, faults and a repair estimate). The camera glides from car to car; leave it alone for a few seconds and it plays film-style shots of the car in focus (press any camera control to take it back). Buying removes the other cars, plays a short reveal you can skip and puts you in your new car.

High-end dealers also take **factory orders**: pick a model, a trim, a colour and the factory options (wheels, interior, steering wheel and so on) and the car is delivered to your garage six game hours later. The models too odd for any lot (quad bike, buggy, crawlers, loaders) are available only here, as special orders.

## Day and night

- **Day** (07:00-19:00): the legal half. Jobs, shops and dealers, the track events (time trials, drag strips, circuits) with prize money, clubs' day events. Money.
- **Night** (21:00-04:00): the street half. Street races, car meets, pink slips, the swap meet. Reputation, worth more with **heat**. Shops and dealers are closed.
- The clock runs slowly inside each half and stops at its end; **Start the night** / **Start the day** (the Wait app or a garage computer) moves on. A new day starts when you start the day.

## Weather and puddles

Each phase of a day has its own weather (clear, cloudy, three strengths of rain, fog at night; the phone's Wait app shows the forecast). In the rain the sky goes grey and dark, the road gets wet and puddles form, with ripples, wheel spray and a mist behind the car; at speed a puddle drags and can aquaplane the car. The roads dry out afterwards. Everything works in any car you drive.

## Car Surface FX (optional)

With the **Car Surface FX** mod installed, dirt and scratches stay with your cars: the fuel station's car wash (roll slowly through a wash bay or choose Wash at a pump) cleans the dirt, Wrench Works repairs buff scratches out, a paint job leaves the car clean, and a stored car keeps its state in the save. **My cars** shows how dirty or scratched each car is. Without the mod nothing changes.

## Car meets

At night, walk up to the owner of a parked car at a meet and press **Talk to <name>**: their story, then a tip, a race word or the car for sale. The owners stand in pairs and trios, the music plays from one car and the crowd murmurs at the middle. The meet fills without freezes because cars are built one at a time while you are slow or far away.

## Racing, heat and the police

- Races are at night, against racers from your phone: for money, high stakes or **pink slips** (win and their car is yours, lose and you walk home).
- **Heat** (1-5) is how much the police want you. It exists only at night, rises with street races, near misses and chases, and the hotter it is the more patrols, the harder to shake, and roadblocks from 4.
- Reputation earned at night is **at risk** until you bank it at a garage (or by starting the day). Busted: a fine, the unbanked reputation, and at heat 4-5 the car is impounded.
- **Clubs** run seven-day seasons (a night race and a day track event each day), **crews** hold the districts of the map (phone > Turf), and a **swap meet** fills a car park on weekend nights.

## The phone and the laptop

The phone (K) has Races, My cars, Bank, Street cred, Jobs, Wait, Settings, Club, Turf, Car market, Part market and Help, with Messages, Contacts, Phone and Cab in the dock. Garage computers (and the other computers on the map) open a Windows-style laptop with the same markets, your cars, the bank and Help, and the garage's own tools.

## Settings

The phone's **Settings** app: police and how hard they are, pay, hardcore mode (no pull-outs, no insurance, no free cab), the clock's speed, traffic in street races, the laptop wallpaper, the **Street Legal dashboard** (off: BeamNG's own HUD is used), a **performance overlay** for reporting stutters and **Record street races** (watch a race again from the Races app and keep a clip).

## Multiplayer (BeamMP)

The career is single-player: it spawns and removes cars, moves you around and keeps its own clock, none of which fits a shared server. With BeamMP installed nothing in the mod errors, and:

- the main menu tile says the career is single-player while you are in a BeamMP session, and its start buttons are not offered; `sl_career.start` refuses with the same note;
- if you join a server while a career is running, the career is saved and stopped (a note says so); it waits for you where you left it;
- everything else the mod adds (the markers, the phone, the ambience, the weather, the drag strip, the rally stages) only runs inside a career, so on a server it is idle.

Detection is BeamMP's own: `MPCoreNetwork.isMPSession()` or `MPGameNetwork.connectionStatus() == 1`. Wrench Works (the garage and the shops) and Wrench Works: Drivers & Pedestrians are separate mods; the garage respawns your car and is best left alone on a server.

## Known issues

- A few stock models (the midtruck) are kept off the lots: they can crash the game on a second lot build.
- Some pedestrians stand still; frame time rises in the busy parts of the map with traffic and pedestrians on.
- The Valo City map and the original cars and traffic of Street Legal Racing Redline are on hold and not part of this release.
- Depth of field, the car lights and the hood opening in the dealers' camera shots depend on each car's own setup; switches for them are in `sl_lot.FX`.

## Also in the repository

The career can also run on the Wrench Works: Valo City map (`slrr_valo_city`); that map is on hold and not part of this release. The dashboard's own art (dials and icons) is not shipped; see `tools/slrr_ui.py`. `docs/integration.md` has the contract with the map and Wrench Works.

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
node tools/hudtest.js     # the dashboard, the same way
python tools/refcheck.py  # every global, hook, cross-mod call and settings key refers to something that exists (needs lupa and the game's lua folder)
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
| `lua/ge/extensions/sl/hud.lua` | the Street Legal dashboard |
| `lua/ge/extensions/sl/carcare.lua` | battery, oil, coolant, wear, fuel grade, nitrous, the trunk, a car's history |
| `lua/ge/extensions/sl/station.lua` | the gas station pumps and shop |
| `lua/ge/extensions/sl/police.lua` | night patrols, heat, the impound |
| `lua/ge/extensions/sl/services.lua` | the garage's Services drawer |
| `lua/vehicle/extensions/slCar.lua` | the same in the car's own Lua: battery, fluids, wear, leaks |
| `lua/common/sl_carcare.lua` | the car care rules |
| `lua/ge/extensions/sl/core/*.lua` | the rules, no game calls: `progression`, `roster`, `market`, `cars`, `builds`, `state`, `rng` |
| `ui/modModules/slPhone/slPhone.js` | the phone's screen |
| `docs/integration.md` | how it fits with the Valo City map and Wrench Works |
