# Changelog

## 0.8.0 (needs Wrench Works 1.8.5)

The career gets things to spend on and things to aim for. Everything marked "not yet seen in the game" is built and tested offline only.

### New
- **The new economy is for new careers; old saves are asked.** Weekly costs, servicing and wear, contracts and tier perks are on from the start in a career created on 0.8.0 or later. A career from before keeps playing as it did: those four are off for that save (your switches in the Mods menu are untouched) and the phone offers to turn them on for it, once, with a button. Nothing is billed backwards when you do. Offline-tested; not yet seen in the game.
- **Weekly costs (new, on by default; ESC > Mods > Street Legal > Parts of the game > Weekly costs):** every 7th day the garage rent (garage 1 free, garage 2 $150, garage 3 $400) and the storage of cars beyond two ($40 a week each) are paid. What you cannot pay becomes a debt at the bank (never a repossession), costs 5 reputation once, and is paid down first from money above $200; the bank lends nothing while you owe it. A ledger on the phone shows the coming bills and the last eight weeks. A save that already exists starts its first week the day it loads, nothing is billed backwards. Offline-tested; not yet seen in the game.
- **Servicing and wear (new, on by default; Mods > Street Legal > Parts of the game > Servicing and wear):** the kilometres you drive now wear a car 40 times as fast (before, the wear model was so slow it never showed), a service is due about every 150 km, and driving past it wears the car faster. A basic service (about $30 plus 0.2% of the car's value) restarts the interval; a full overhaul also puts the worn sections right, at the price the car report quotes. Half as much again without a workbench in the garage. The wear a car already has when you first load it counts as it did before; only the driving from then on counts 40 times. With Part Wear installed (a version with the read-only conditions query) its per-part conditions are shown per section; without it the career's own wear model runs. Off: the old slow wear and no service. Offline-tested; not yet seen in the game; the Part Wear query is not yet in a Part Wear release, so only the own-model path has been exercised.
- **Wear rate and service interval (new setting; Mods > Street Legal > Difficulty > Wear):** 0.5x (parts last twice as long, service every 300 km), 1x (service every 150 km, the default), 2x or 4x. It sets the wear of the career's own model and, when they are installed, tells Part Wear (a version with `setWearRate`) and the Car Surface FX tyres (a version with `setWearScale`) to wear at the same rate. Wear already there stays as it is; changing the setting restarts the service clock. Offline-tested; not yet seen in the game, and the Part Wear and tyre calls have only been tested against stand-ins until those mods ship them.
- **Contracts (new, on by default; Mods > Street Legal > Parts of the game > Contracts):** from 100 reputation, up to two of the part runs and courier parcels on the Jobs board come with terms: no damage, within 80% of the time limit, delivered in the rain (only offered when the road is wet), or in a car worth $15,000 or more. Keep them and the job pays 1.6 to 2.2 times as much and gives 5 extra reputation; miss them and you get the normal pay. Off: no terms, normal pay. Offline-tested; not yet seen in the game.
- **Tier perks (new, on by default; Mods > Street Legal > Parts of the game > Tier perks):** every boss you beat gives a lasting advantage: from rank 2 garage upgrades cost 10% less and services 15% less; rank 3 jobs pay 10% more; rank 4 police fines are 20% lower; rank 5 the bank lends 25% more; rank 6 (all bosses beaten) completes the set. Saves that already count bosses as beaten (older careers) have the perks at once. Off: no advantages. Offline-tested; not yet seen in the game.
- **Danger zones (new, on by default; Mods > Street Legal > Parts of the game > Danger zones):** the longest jump you fly is recorded anywhere on the map (a jump is at least 0.4 s in the air) and pays $150, $300, $600 and $1,000 for 20, 40, 70 and 110 m, each once. Two drift zones on long roads score your drift points between their two gates (fast and sliding between 15 and 80 degrees counts); 600 points pays $300 and 5 reputation the first time. Offline-tested; not yet seen in the game; how high a car must be off the ground to count as flying is a guess to check.
- **Speed traps and speed zones (new, on by default; Mods > Street Legal > Parts of the game > Speed traps):** six traps and two zones on long straight roads of the map, chosen once for your career. Drive through a trap and your speed counts; drive between the two gates of a zone and your average speed counts. Each has a target; the first time you beat it it pays ($250 for a trap, $400 for a zone) and gives 5 reputation; after that only your personal best changes. The phone list is built by the phone. Offline-tested; not yet seen in the game.
- **Cinematic moments (new, on by default; Mods > Street Legal > Parts of the game > Cinematic moments):** Start the night and Start the day play a short full-screen scene (the sky, the moon or sun, the city lights, a title card) instead of the plain fade; and short banners over the live game mark a bust, an impound, a pink slip won or lost, the heat going up, a new car, a bigger garage, the green light and (with Wrench Works 1.8.8 or newer) the garage door. Any key skips a scene; the Reduce motion setting gives a still card. Offline-tested with a frame proof in a browser; not yet seen in the game.
- **Used-car checks (new, on by default; Mods > Street Legal > Parts of the game > Used-car checks):** a private ad for a car shows its history (owners, service record, accidents) but not its faults or the car report; a mechanic check ($40 plus 0.5% of the price) shows both and what each fault costs to fix. A patchy service record is a hint. Dealers, auctions and the swap meet are unchanged. Off: the ads show every fault, as before. Offline-tested; not yet seen in the game.

### Changes
- **Phone cards:** the Bank page shows the weekly costs; My cars shows each car's service card; private car ads show the history and the Check button; the Jobs page tags contracts; Street cred lists the tier perks.
- Servicing, weekly costs, contracts and tier perks are on by default, so an existing save feels them at once (rent, storage, repair costs, prices): switch each off in Mods > Street Legal > Parts of the game. Wear already on a car counts as before.
- The race log is written at most once a second (it was rewritten on every line); a flush at the end of the career and of the level.
- Car commands that call back into the mod are guarded; the options file is never written over when it could not be read; `sl/debugCars.lua` (a tester's cheat-car list) is loaded only when the file exists and is not in the zip.
- A material whose file the game reports as nothing counts as a car's (the wet-world glass), so the wet world leaves it alone. Wet roads and walls stays off by default.
- Starting a career removes the free-roam car the player was in (it overlapped delivered cars).
- README and the player guide are up to date; the README says what ships and what does not.

## 0.7.2 (needs Wrench Works 1.8.5)

Hotfix for 0.7.1 and every release since the spike strip came in.

### Fixes
- **A spike strip no longer freezes the game:** at heat 3 and above, when a chase placed a spike strip ahead of you, the placing code failed every frame, filled the log with thousands of error lines and could hang the game. Fixed, and the chase check now switches itself off for the session after five failures in a row instead of failing every frame. Found by the tester in the chase regression; offline-tested; not yet seen in the game.
- A car delivered from a factory order could be built with no direction when the forecourt lookup answered with a position only. Fixed in the same sweep (the same mistake in the code, now caught by a check that fails on it).

## 0.7.1 (needs Wrench Works 1.8.5)

Fix release for 0.7.0.

### Changes
- **No start warning:** BeamNG 0.40 logged "Please make sure to call setExtensionUnloadMode("gameplay_drag_core", "manual")" at game start; the mod now sets that first. Not yet seen in the game.
- **Phone skins:** in the built 0.7.0 zip both Classic and Slate are listed (seen in the game). The skin reader now logs once if a failure stops it listing skins, instead of failing silently.

## 0.7.0 (needs Wrench Works 1.8.5)

### New
- **Phone skins (new, off by default):** ESC > Mods > Street Legal > Screens and texts > Phone skin. Classic is the default and the phone is unchanged. **Slate** is a modern look of our own (squircle tiles, outline icons, a pill camera island). You can add your own skins as folders in the user folder (`settings/street_legal/phone_skins/<id>/skin.json`); see docs/PHONE_SKINS.md. Seen in the game (Classic and Slate both listed and applied, back to Classic works; a phone that is already open keeps the old look until you close and reopen it). Not tested: your own skin folders, and a skin from another mod.

- **Street Legal in free roam (new, all off by default):** ESC > Mods > Street Legal > Free roam. A master switch, "Use Street Legal features in free roam", and one switch per feature: Phone (K) with the Maps and Cab apps, Maps, Map pins (shops, garages, car washes and gas stations on the big map; meets are pins only), Weather (with wet roads and puddles, on the game's clock), Cab (free), Car wash (free), and the Dashboard. No career is started or saved, no money is spent or taken, and the career apps, shops and jobs are not part of it. Seen working in the game at Low graphics: the weather (the sky follows the clock and goes back when the switch is turned off), the dashboard (the Dashboard setting in Screens and texts must be on too), the phone (K: only the Map and Cab apps, the clock, no money; it names the map you are on), the Map app (shops, garages, car washes and car meets with their distances, and a route on the road), the free cab (it ends with "That was $0."), the free car wash, and that no career save file is touched. Not yet seen on screen: the pins on the big map (the game was given them, but the big map did not draw any pin in the test).

- **Billboards, a fallback (off by default):** when the mod ships only its own five ads of each name, it can draw the game's sign atlas over them in the game, a few milliseconds a frame. Not yet seen in the game.

### Changes
- **Wet roads and walls** stays off by default (0.6.1) with its warning: five tests at High graphics lost the graphics device within a minute of heavy rain with it on, and the cause is not found; notes in docs/WET_WORLD_HIGH_CRASH.md. Two additions for whoever looks at it next: materials the game reports with no file (the lamp glass of loaded cars) are never edited by it any more (this did not stop the crashes), and a Developer row, "Log each wet-world material edit", writes the material being edited to the game log.
- **Garage entry:** a visit the career refuses (a garage above your street cred) now says why on screen, and the car garage's enter calls return false with the reason.

## 0.6.1 (needs Wrench Works 1.8.3)

Hotfix for 0.6.0.

### Changes
- **Wet roads and walls** is now off by default and switched off once for everyone, because it is what crashes the graphics driver at High graphics in heavy rain on BeamNG 0.40. You can turn it back on in Mods > Street Legal (the row carries the warning); a player who turns it back on keeps it. Puddles, rain and the rest of the weather are unchanged.

### Known issue
- With Wet roads and walls on, a heavy-rain crash can still happen at High graphics. With it off it was not seen (a 10-minute High-graphics heavy-rain test with it off, and puddles on, did not crash).

## 0.6.0 (needs Wrench Works 1.8.3)

### New
- **Parts of the game you can switch off** (Mods > Street Legal > Parts of the game, and the Active features page; all on by default): spectators, sponsor billboards, ambient sounds, puddles and splashes, achievements, getting-started tips, car and part markets (classifieds and auctions), rally stages, street races and drag racing, clubs, crews and turf, the tow truck, the taxi ride, and jobs. A part that is off does nothing and loses its phone app; switched on again it carries on from your save (nothing is deleted). Six more core parts have a switch too: the bank (cannot be switched off while a loan is open: "Pay back the loan first"), the hospital (off: injuries cost and stop nothing; hardcore death needs it on), the HUD phone pill, the laptops, Maps and garage upgrades (off: the garage has every tool). The phone itself has no off switch. The bank switch is global: a loan open in another career is frozen (no interest, no payments) while the bank is off. A hardcore career cannot switch the hospital off. When the clubs come back on, a season that was not simulated while they were off is closed with no reward and a new one starts. Off for the tow truck: a car left out is brought round without a truck; off for the taxi: the Cab app still takes you there, at once. Bank and Hospital switches seen in the game; the other switches are not yet tested.

- The main switches (police, crew raids, race flares, dashboard, race recording, weather, wet world and tarmac, spike strips, pursuit breakers, night race kinds, rivals, photo of a new car, the Maps speed and the phone's K slide) are tagged for the Active features page of the Mods menu.

- **Tyres keep their wear with the car** (needs Car Surface FX with its tyre simulation switched on): a car's tyre set and how worn it is are saved with the car, and put back when the car comes out of the garage or you reset it. Buying a different tyre part, or the same one again, gives a new set; a car sold on bare rims shows no tyres until a tyre part is fitted. Tested in game with a bought car on a reset, a respawn and a career save (the Wrench Works garage fitting itself was not tested in game).

### Changes
- **Wet roads and walls** now change one material at a time instead of several, so getting wet takes longer (about a minute and a half in a sudden downpour). It did not stop the High-graphics crash (see the known issue).
- **Wet world and ground hollows:** the wet world takes turns with Car Surface FX's ground hollows (tested at Low graphics).
- **Wet tarmac:** off by default (as in 0.5.2). It waits for puddles (a 60-second hold); with it, in one heavy-rain test at Low graphics with wet tarmac on, it no longer crashed. It may still crash some cards.

### Known issue
- At High graphics a heavy-rain crash (the graphics driver stops) can still happen, also with the slower wet-road pace above; it was not seen at Low graphics. Workaround: turn "Wet roads and walls" off, or lower the graphics quality in heavy rain.

## 0.5.2 (needs Wrench Works 1.8.0)

Hotfix for 0.5.1, for BeamNG 0.40.

### Fixes
- **Crash fix:** on BeamNG 0.40, Street Legal's rain could crash the graphics driver when the wet world and puddles updated at the same time. They now take turns, and the wet world changes fewer materials per second. In our tests, a heavy-rain run that crashed every time before ran 8 minutes without a crash; tell us if you still see one.

### Known issue
- The crash fix was tested at Low graphics. At High graphics a heavy-rain crash has still been seen. Workaround: turn "Wet roads and walls" off, or lower the graphics quality.

### Changes
- **Wet tarmac** (the darker road surface in rain) is now off by default and switched off once for everyone. You can turn it back on in Mods > Street Legal. Turning it back on can still crash some graphics cards on 0.40.
- **Puddles:** in a sudden downpour, puddles now appear gradually over the first half minute.

## 0.5.1 (needs Wrench Works 1.8.0)

Hotfix for 0.5.0.

### Fixes
- **Big map:** every marker we list now carries a date. The game's mission marker sort threw 'compare two nil values' on every frame where two markers overlap (the auction on the junkyard), which stopped routes and markers on the big map. Offline tests pass; not yet confirmed in game.
- **Car fluids:** the oil and coolant lookup in the car is guarded, so a build that blocks the lookup does not throw on every call. Offline tests only; not seen in game.

## 0.5.0 (needs Wrench Works 1.8.0)

What is new since 0.4.0, for players.

### Built, not yet tested in game
Built, with offline tests, but not yet seen working in the game. An item leaves this list only when the tester posts a pass.
- **Phone:** Camera and Gallery (photos, wallpapers, a photo of every car you buy), Map (places by kind, a route on the road, Route to my garage), Contacts with the people you have met (rivals, crew leaders, dealers) and a Route to button.
- **Rivals and the campaign:** six named rivals with texts, a rivalry meter, pink slips only as an offer on their card, tier bosses, and the campaign end (the last boss).
- **Day jobs and economy:** tow jobs, scrapyard parts runs, taxi fares with a tip for a smooth ride, dealer deliveries judged by scratches; the balance settings (jobs, bank, markets, services, start money, heat, racers); hospital costs; car auctions (online lots and the live junkyard auction).
- **Police:** deeper chases (spike strips, pursuit breakers), the nemesis cruising at night.
- **Cars:** career dirt (used and delivered cars carry the dirt their condition and mileage give them; the car wash takes it off), deliveries that are never built on top of a car on the forecourt.
- **Car Surface FX:** snow, frost, bugs, wipers, road spray, puddle splash and the mud look, and the features ported from Surface FX (skid marks, ruts, leaks, debris, sparks, grass).
- **The Mods menu (ESC > Mods menu):** every setting of our mods in one place, with tabs, groups and a reset per tab; Street Legal, Wrench Works, graphics and camera (anti-aliasing, sharpening, Look, cinematic camera), Pedestrians & Drivers (driver tunables, rigged driver options, clothing colours) and Car Surface FX are on it. The settings on the phone, the laptop, the garage screen and the game's Options page are removed in its favour.
- **Night races:** more variety: a street race can now be a city run, a highway run, a hill climb or a rolling 60-130 run. The goal is picked from the road graph (length, share of fast road, tarmac, turns, height gained, no dead ends), and the challenge card says which kind it is.
- **Drivers:** the driver tunables and the injury effects. The rigged driver is now the default for your own car (switch to Props in Mods > Driver model if you see problems); every other car keeps the prop driver.
- **The Mods menu look:** each row is a title and a control on one line, with the help text in a side panel like the game's Options (shown on hover and on keyboard or controller focus); tabs whose settings are all advanced show them; the reset button is no longer under the career HUD.
- **Wet world, small parts:** the warmer grey of each wetness tier on the road, and the phone fitting a 3440x1440 screen (it was seen at 1920x993).

### Weather and puddles
Seen working in the game by the tester:
- **A wet world in rain:** roads, markings, walls, paving and plaster darken and turn glossy and reflective as the rain lasts (light, medium and heavy rain each go further), the tarmac of the terrain too, in three steps; in heavy rain the concrete wall is clearly darker and wet-looking. Materials are changed a few at a time, the slow ones only while the car stands still or the game is paused, so nothing stalls while you drive (no frame over 50 ms in a drive in heavy rain); everything is wet about 50 seconds into heavy rain and dries over about four minutes after it. Switch it off in ESC > Mods menu > Street Legal ("Dark glossy tarmac in rain"); the materials go back exactly.
- **Overcast skies in the rain:** the clouds thicken in light, medium and heavy rain, so it no longer rains from a sunny sky.
- **Puddles:** up to 300 (setting "Puddles in the rain", 10-300), placed 140 m or more away once the shower is under way and growing as the rain lasts, so none appears in view; varied pools, damp patches and wheel-track lines; small spray from the wheels through one; rain falls only around you.
- **A moodier rain sky:** the sun, ambient light and fog colours go grey and dark in the rain, and dusk no longer turns orange under cloud.
- **Puddles that look like water:** greyer and darker with a soft rim, never on a kerb or step; wheel spray and a wet-road mist behind a car, short wet trails, and drag and aquaplaning when you hit one at speed. Rain rings ripple on the puddles, gusts change how much falls and the wind drifts; damp patches breathe as the road dries.
- Puddles, spray and wet-tyre grip work in whatever car you drive, not only the cars of your fleet.

### Car Surface FX (optional mod)
- With **Car Surface FX** installed, the dirt and scratches it puts on a car belong to your career: the fuel station's car wash cleans the dirt off, the Wrench Works repair buffs the scratches out, a paint job leaves the car clean and unscratched, and a stored car keeps its dirt and scratches in the save. **My cars** says how dirty or scratched each car is ("Clean, heavy scratches"). Nothing changes without the mod.

### Dealers
- The game's own HUD apps, minimap, messages and tips, our dashboard, the phone pill and the heads-up are all hidden while a lot is open or the purchase reveal plays, and come back after.
- The car report is a panel of its own that fits the screen (about 80% high, centred), with collapsible sections showing condition, worst fault and repair estimate, scrolling by wheel, drag and the pad's stick; the compact card stands above the letterbox bars.
- The camera keeps the car in the middle of the screen; the card shrinks to a bar while the cinematic shots play.
- An error during a purchase can no longer leave the bars or the game's UI stuck.

### Car meets
- On foot, walk up to an owner's parked car and press the game's prompt (**Talk to <name> (<car>)**): you get their story and their offer (a tip, a race word or the car for sale). Nothing pops up by itself while you walk through.
- Owners stand in pairs and trios; the music plays from one car and the crowd murmur is at the centre.
- A meet fills without freezes: one car is built at a time, the gap between cars follows how you drive (4 s when you stand, 10 s when you are slow, 16 s when you are moving, 25 s when you are fast), and no car is built while you drive fast nearby.
- Meets come more reliably: the first meet of a night is tried 30 seconds in and a miss is retried 20 seconds later. A meet that could not build any car (you kept driving fast nearby) is closed and does not count, so the next try comes.

### Economy
- Day jobs pay 35% more.
- Garage 2 needs **175 reputation and $6,000** (was 1,500 and $25,000); garage 3 needs 1,000 and $25,000 (was 3,000 and $75,000). The first garage upgrade is reached in a few hours of play.

### Smoother running
- **Far fewer freezes at night.** Nearly every remaining stutter was a car being built (1.1-1.8 s). Builds are now one at a time anywhere in the game with a 20 s gap, not while you drive fast, and a racer's car that is waiting in the pool is chosen first and put back instead of built again. Ambient police patrols follow the same rule (a chase, a race start and heat 4-5 patrols still come at once), night cruisers are built behind the black fade where there is one, and custom cars are built in one spawn and remembered. In a clean night drive (heat 0) the frames over 50 ms went from 102 to 10, and the worst frame from 81 ms to 55 ms.
- **Weather costs almost nothing:** the rain box and the sky tint no longer cost a few milliseconds every frame (heavy rain went from 9.2 ms a frame to 0.8 ms; a clear night from 0.58 ms to 0.09 ms), and the puddles do nothing on a dry road.
- The race route check is made four times a second instead of every frame.
- The phone, laptop and dashboard are sent only what changed: a screen is not rebuilt when its data did not change (no more lost clicks, lost typing or jumping scroll), and the dashboard updates ten times a second with the needles easing between updates.
- Night cruisers are built while the screen is black at the start of the night, a fast travel or the career start, so cars appear without a gap or a freeze.
- Racers' car models are loaded one at a time at quiet moments. A hitch recorder (for reporting stutters) lists every frame over 50 ms and what ran just before it.

### Accessibility
- **Colour-blind friendly colours** (Settings): blue and orange instead of green and red on the phone, the laptop and the HUD, with a mark (a tick, a cross, an arrow) beside every good or bad figure.
- The text size setting applies to the phone, the laptop, the HUD and the lot cards; on a pad the phone is never smaller than Large. Whatever has the pad's focus has a thick yellow ring. The text of our panels is checked for WCAG AA contrast.
- **Show co-driver notes on screen** (Settings, on by default): a rally stage also writes what the co-driver calls.

### Names
- The pieces are called by their player-facing names everywhere: the Street Legal dashboard, Wrench Works: Drivers & Pedestrians, Street Legal Racing Redline in the credits.

### Fixes
- No doubled garage marker on the map and in the world (seen in the game).
- A car never becomes unspawnable: only parts that can come off are dropped from a damaged saved setup, never the body, frame or engine.
- Recorded damage waits for the car to settle before it is applied.
- The phone's text size scales the page body, not the whole screen.

## 0.4.0 (release 1 candidate; needs Wrench Works 1.7.0)

The career now runs on **West Coast USA**, BeamNG's own map, with a day and a night half to every day. Valo City (optional) is on hold and not part of this release.

### Career on West Coast USA
- A new career asks which map; the save remembers it. Texts name the map you are playing on.
- The map's own dealerships, garages, gas stations and computers become career places: each dealer sells from its own list, new or used; garages above your reputation are closed ("You need N reputation"); every lot, garage and shop is a fast-travel point on the big map (no repair on the way).
- Walking markers and prompts at the lots ("Look at the cars", "Sell your car"); a dealer shows its cars to a driver as well as to a player on foot.
- Laptops: walk up to a computer, or stop a car at one, and "Use the laptop" opens a full-screen Windows-style desktop (My cars, My parts, Car market, Part market, Bank, Street cred, Help, and the garage's own tools: part customization, tuning, painting, repair).
- Walk into a garage door on foot: a panel takes a car out, works on it, or puts it away. A car you stored is fetched when you walk in.
- The cab drives up from out of sight, takes you to any place by category (garages, shops, dealers by price tier, junkyards), and a ride to a lot ends in its car park.
- A Wait app skips to the next morning or 1, 3 or 6 hours (refused in a race, on a job or with the police after you).
- Loans: the limit grows with your reputation, your garage and half the value of your cars; a missed weekly payment costs reputation. Insurance premiums start at $80 and rise $60 per claim in the last 28 days.
- Tutorial: a courier run where the map has no parts shop.
- The city starts with traffic and parked cars.

### Day and night, heat
- Every day has a **day** (07:00-19:00, the legal half: jobs, shops, dealers, track events with prize money) and a **night** (21:00-04:00, the street half: street races, car meets, pink slips, the swap meet). The clock runs slowly inside each half and stops at its end; **Start the night / Start the day** (Wait app or a garage computer) moves on. The sky follows (dark from 20:00).
- **Heat** (1-5) exists only at night: street races, near misses and chases raise it; patrols get stricter, roadblocks come at 4. Reputation earned at night is at risk until you bank it at a garage; getting busted costs a fine and the unbanked reputation, and at heat 4-5 the car is impounded.
- A Day/Night badge with heat flames on the driving HUD and in the phone's corner; the clock speed is a setting. BeamNG's own HUD is the default; the Street Legal dashboard is optional.

### Dealers and buying
- **Lots** show four to six cars of the dealer's own price tier, standing in the map's painted parking bays, with a card each: test drive, buy, **show full car report** (every part by section with condition, dents, faults and a repair estimate). A lot shows a loading screen while the cars come out.
- **Buying** removes the other cars, plays a short reveal of the car (cuts through its details, then a smooth move behind it) that you can skip, and puts you in the car where it stands.
- **Cinematic browsing:** a slow dolly between cars with a low shot of the car in focus; leave the camera alone and it plays shots of the car in random order (sweeps along the nose and sides, wheels, badge, tail lights, exhaust, a high orbit, the cabin from the driver's seat and the passenger's, the engine bay with the hood opened) between letterbox bars, with the car in focus, its lights on and a slow zoom; touching the camera ends them.
- **Factory order** at high-end dealers: a catalogue of every model the dealer sells with all its trims and the special-order models, a spec screen with only factory options (paint swatches, interior, wheels, steering wheel, mudflaps, bumpers, spoilers, motors, with a live price), delivery to your garage after six hours. Pending orders show in My cars on the phone and the laptop.
- **Special order only:** the quad bike, buggy, rock crawlers, dump truck, loaders, props and trailers are in no lot, ad or traffic: they are available only from the factory catalogue.
- Dealers, the junkyard and the scrap yard open 08:00-17:00 (dealer 09:00-17:00) and say "Closed. Opens at HH:00" outside those hours. The junkyard always has a starter car at or under $3,500; you start with $5,000.

### Phone and laptop
- Two marketplaces: **Car market** (dealers and private ads) and **Part market** (Revline, Swap & Bid, the paper, the Wrench Works catalog), on the phone and on every laptop, with the same pictures, years, mileage, drivetrain, power, seller, distance and delivery time as the stock shop shows. Every ad has a picture, a part ad names the part and the car it fits, and parts have their own pictures.
- A Settings app, Android style, with every setting grouped; Help on the phone and every laptop (also in `docs/PLAYER_GUIDE.md`).
- The phone opens on its home screen each time; gamepad: B leaves a lot, a meet or a gas station, and the right stick and zoom buttons move the lot camera.

### Races, drag, rally
- Street racers are road cars (no limos, buses, vans, trucks or police cars) and cruise the main strips first; stop beside one or flash it to race; a racer you flash pulls over and you start from a stand. A race-route preview map on the challenge card, a tall finish marker, both cars lined up on the route's first road.
- **Drag strip:** the game's own tree, staging, reaction time, ET, trap speed and timeslip with bracket racing, by day.
- **Rally stages:** four dirt and gravel stages as day events with pacenotes read from the road's curvature.
- **Race of Champions** at the race track as the finale for garage 3 and 6000 reputation.
- Clubs run seasons with a night league and a day league; crews hold the districts of the map (phone > Turf); a swap meet fills a car park on weekend nights.
- **Replay:** the last street race can be watched again and kept as a clip.
- Stock missions pay by type (evade, parking, time trials).

### World: weather, traffic, meets
- **Weather:** a state per phase of each day (clear, cloudy, three strengths of rain, fog banks at night), with wet roads that dry out, puddles, wet-tyre grip and jobs that pay more in bad weather.
- **Car meets** with a rotating theme (JDM, muscle, drift, euro): parked cars in the painted bays, owners who wave back, spectators; nothing appears in your sight.
- **Spectators** beside the drag strip, round the race track and at every meet spot.
- **Ambient sound:** waves at the water's edge, the roar of a wide road, a crowd in town by day, music and crowd at a meet.
- **Billboards** on the map carry your sponsor.
- Gas stations: a pump prompt, the station's own petrol price and a car wash.
- Cars wear: how you drive (limiter, overheating, hard stops, launches, landings) turns kilometres into condition lost per section.

### Fixes and calmer running
- Money exploits closed: faults are put right only by a part in the slot and pay at most 1.35 times its cost; a race you cannot cover is refused; the hot-car job pays less.
- A teleport, a fast travel, a tow or a respawn never repairs a car; a car's damage survives a purchase.
- A full tank says so; a part name is never shown as "table: 0x...".
- Parts that fell off on the road are no longer part of the car in the garage.
- The test drive stays until you are back on foot at the lot; a car you bought or test drove leaves the lot on the nearest city lane.
- Jobs count a stop by distance along the ground; a diner's stop covers its whole row of pumps.
- Fewer per-frame costs; the lot's cars are built one at a time and no car is respawned in place; a performance overlay (off by default) shows frame time, VRAM and counts for reporting stutters.
- The career does not start in a multiplayer session and stops cleanly if you join a server.

### Not in this release
The Valo City map and its venues are on hold; the original cars and traffic of Street Legal Racing Redline are not part of this release.
