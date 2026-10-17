# Changelog: Wrench Works: Street Legal (the career)

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
