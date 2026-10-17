# Wrench Works: Street Legal

A street-racing career for BeamNG.drive on **West Coast USA**, in the spirit of *Street Legal Racing: Redline*. You start on foot with a few thousand dollars and no car. Buy something that runs, fix it up in the garage, earn money by day, race the streets by night, keep ahead of the police and build a name: from a beater to the best in town.

Part of the **Wrench Works** family. BeamNG.drive 0.39.

## What you need

- **Wrench Works: Garage** (`wrench_works.zip`): the garage this career works in. Required.
- **Wrench Works: Drivers & Pedestrians** (`slrr_drivers.zip`): a driver in every car and people on the sidewalks. Optional, recommended.
- The map **West Coast USA** that comes with the game.

The download **Wrench Works Street Legal - West Coast** has all three in one file, with the versions each one needs of the others.

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

## Day and night

- **Day** (07:00-19:00): the legal half. Jobs, shops and dealers, the track events (time trials, drag strips, circuits) with prize money, clubs' day events. Money.
- **Night** (21:00-04:00): the street half. Street races, car meets, pink slips, the swap meet. Reputation, worth more with **heat**. Shops and dealers are closed.
- The clock runs slowly inside each half and stops at its end; **Start the night** / **Start the day** (the Wait app or a garage computer) moves on. A new day starts when you start the day.

## Racing, heat and the police

- Races are at night, against racers from your phone: for money, high stakes or **pink slips** (win and their car is yours, lose and you walk home).
- **Heat** (1-5) is how much the police want you. It exists only at night, rises with street races, near misses and chases, and the hotter it is the more patrols, the harder to shake, and roadblocks from 4.
- Reputation earned at night is **at risk** until you bank it at a garage (or by starting the day). Busted: a fine, the unbanked reputation, and at heat 4-5 the car is impounded.
- **Clubs** run seven-day seasons (a night race and a day track event each day), **crews** hold the districts of the map (phone > Turf), and a **swap meet** fills a car park on weekend nights.

## The phone and the laptop

The phone (K) has Races, My cars, Bank, Street cred, Jobs, Wait, Settings, Club, Turf, Car market, Part market and Help, with Messages, Contacts, Phone and Cab in the dock. Garage computers (and the other computers on the map) open a Windows-style laptop with the same markets, your cars, the bank and Help, and the garage's own tools.

## Settings

The phone's **Settings** app: police and how hard they are, pay, hardcore mode (no pull-outs, no insurance, no free cab), the clock's speed, traffic in street races, the laptop wallpaper, the **SLRR dashboard** (off: BeamNG's own HUD is used), a **performance overlay** for reporting stutters and **Record street races** (watch a race again from the Races app and keep a clip).

## Also in the repository

The career can also run on the Wrench Works: Valo City map (`slrr_valo_city`); that map is on hold and not part of this release. The SLRR dashboard's own art (dials and icons) is not shipped; see `tools/slrr_ui.py`. `docs/integration.md` has the contract with the map and Wrench Works.

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
| `lua/ge/extensions/sl/hud.lua` | the SLRR dashboard |
| `lua/ge/extensions/sl/carcare.lua` | battery, oil, coolant, wear, fuel grade, nitrous, the trunk, a car's history |
| `lua/ge/extensions/sl/station.lua` | the gas station pumps and shop |
| `lua/ge/extensions/sl/police.lua` | night patrols, heat, the impound |
| `lua/ge/extensions/sl/services.lua` | the garage's Services drawer |
| `lua/vehicle/extensions/slCar.lua` | the same in the car's own Lua: battery, fluids, wear, leaks |
| `lua/common/sl_carcare.lua` | the car care rules |
| `lua/ge/extensions/sl/core/*.lua` | the rules, no game calls: `progression`, `roster`, `market`, `cars`, `builds`, `state`, `rng` |
| `ui/modModules/slPhone/slPhone.js` | the phone's screen |
| `docs/integration.md` | how it fits with the Valo City map and Wrench Works |
