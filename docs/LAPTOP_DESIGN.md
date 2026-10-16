# The laptop on West Coast USA (T28, design only)

Worker A, 2026-10-17. Decision D-2026-10-17c: keep what the stock career's laptop does, in Street Legal's look; no change where ours already does the job. Read-only study; nothing built or run. Game Lua: `I:\SteamLibrary\steamapps\common\BeamNG.drive\lua\ge\extensions\career\modules\` (written `m/`). Stock UI read for layout only: `ui\ui-vue\src\modules\career\views\ComputerMain.vue`, `ComputerWrapper.vue`.

## 1. The stock laptop

`m/computer.lua` opens at a computer facility (`openMenu` :18). It lists the cars in the closest garage (:24), then broadcasts `onComputerAddFunctions` (:41) and every module adds tiles. A tile exists only if the **computer's own `functions` table** has its key (e.g. `tuning`), so the five WCUSA computers differ. The tile list below is exactly what the stock modules add:

| tile (id) | where added | kind | what it does for the player |
|---|---|---|---|
| My vehicles (`vehicleInventory`) | `inventory.lua:1199` | general | the car list: pick one, rename, plate, favourite, sell, take out of storage |
| My parts (`partInventory`) | `partInventory.lua:684` | general | parts owned and not fitted; sell or fit them |
| Vehicle marketplace (`vehicleShop`) | `vehicleShopping.lua:1059` | general | every dealer's and private seller's listings, remote purchase with delivery |
| Insurances (`insurances`) | `insurance/insurance.lua:1668` | general | choose a policy, driver score, claims history |
| Driver abstract (`playerAbstract`) | `playerAbstract.lua:14` | general | the player's career statistics page |
| APM landing page (`apmLandingPage`) | `branches/landing.lua:739` | general | the skills/branches overview (progress) |
| Part customization (`partShop`) | `partShopping.lua:974` | per car | the part shop for the selected car: browse, cart, fit |
| Tuning (`tuning`) | `tuning.lua:349` | per car | suspension, gearing, tyre pressure and the like |
| Painting (`painting`) | `painting.lua:215` | per car | colours and finish |
| Repair (`repair`) | `insurance/repairScreen.lua:43` | per car | damage list, repair price, insurance claim |
| Performance index (`performanceIndex`) | `vehiclePerformance.lua:585` | per car | a certified performance class by a test run |

Gating: all need a bought starter car (`hasBoughtStarterVehicle`, `computer.lua:39`), per-car ones also `career_modules_permissions` tags (`vehicleRepair`, `tuning`, `vehicleModification`...) and "needs repair first" (`partShopping`, `painting`, `tuning`).

**Which computer has what** (from `facilities.facilities.json`): `servicestationGarageComputer`, `commercialGarageComputer` and `commercialGarageComputer2`: everything above. `alderDragwayGarageComputer`: vehicleInventory, partInventory, partShop, tuning. `servicestationOfficeComputer`: only vehicleShop, partShop, apmLandingPage (no cars listed: an office, not a garage).

**Layout** (`ComputerMain.vue`): title "<facility> home screen", a status card (money), a "Vehicle management" band with the car tile row and left/right buttons (`tab_l`/`tab_r`) then that car's function tiles; a "General computer functions" band with the other tiles; a line of text under the tiles with the reason when a tile is greyed.

## 2. What already delivers it, what is missing

| stock tile | Street Legal / Wrench Works already | missing | verdict |
|---|---|---|---|
| My vehicles | `sl_fleet.list` (`fleet.lua:302`), phone "My cars": use, tow (`:191`), release; sale at lots (`lot.lua:376`) | nothing; the data exists | **REUSE**: laptop tile shows the phone's car list (S) |
| My parts | WW shelf (README "Ordering parts"): parts taken off and delivered live on the garage shelf; sell tool (`garage.lua` `sell`) | a list outside the garage | **ADAPT**: read-only shelf list + "open the garage" (S) |
| Vehicle marketplace | physical lots (`lot.lua`, T12/T22): per-dealer stock from the stock filters; private ads (Revline) are release 2 (T25) | **remote purchase and delivery**; today you must walk to the dealer | **NEW** (M): a dealer list with each dealer's offers (`market.offers`, same seed as the lot, so the same cars), price, buy, car arrives at the garage forecourt after a delay (`fleet.deliver`, `fleet.lua:209`) |
| Insurances | `sl_bank.insure` weekly premium, half of repair/impound bills over a deductible (`bank.lua:48,67`), loan | a policy list (stock has tiers) | **REUSE**: show our bank page (borrow, repay, insure); no tiers (S) |
| Driver abstract | phone "Street cred": title, rep, achievements, records (`achievements.lua:42`, `phone.lua:58`) | none | **REUSE** (S) |
| APM landing page | street cred ladder (`progression.titles`), jobs, garage ladder | skills/branches do not exist in SL | **SKIP** (our rep ladder replaces it) |
| Part customization | WW Catalog: every part that fits, cart, delivery or shop pickup (WW README "In the garage", `garage.openCatalog` `:2147`, `checkout` `:2158`) | opening it from the laptop for the chosen car | **ADAPT** (M): needs a WW entry that opens the garage on that car already in catalog mode |
| Tuning | WW Tune mode (screwdriver), `garage.setMode` `:2144`, `requestTuning` `:2162` | same entry | **ADAPT** (same glue as above) |
| Painting | WW paint booth | same entry | **ADAPT** (same glue) |
| Repair | WW "repair all" (`garage.repairAll` `:2145`), repair tool, SL insurance pays half over deductible | quote shown on the laptop | **ADAPT** (S): list damage and cost from WW, button runs the repair in the garage |
| Performance index | WW Car info + dyno (power/torque curve), SL race classes | a certified class | **SKIP** for release 1 (dyno covers it) |

## 3. Where the laptop works

Follow the stock facility table: each computer's `functions` key decides its tiles; read it at runtime (`freeroam_facilities.getFacilitiesByType('computer')`, as `sl/computer.lua` already does for the prompts). Rules:
- **Garage computers** (`servicestationGarageComputer`, `commercialGarageComputer` x2, `alderDragwayGarageComputer`): car-specific tiles (customization, tuning, painting, repair) act on a car **standing in that garage** (the stock list is "closest garage", `inventory.lua:36`); the car is brought into the WW garage for the work.
- **Office computer** (`servicestationOfficeComputer`): marketplace and parts shop only, no car tiles.
- **Anywhere else** (phone): unchanged. The phone keeps its own apps; the laptop is the big-screen version of cars, bank, street cred and the dealers, plus the garage jobs.
- Not before the first car (as stock `hasBoughtStarterVehicle`), and not in a race or job (`sl_lockdown`/jobs state), with the reason text under the tile.
- Clubs, crews and Revline are release 2 (T25): no tiles on WCUSA.

## 4. The UI

One laptop screen in the **slPhone visual language** (`slPhone.js`): font Roboto/Noto Sans/Segoe, ink `#e6e1e5`, secondary `#cac4d0`, surfaces `#141218` / cards `#211f26`, accent `#a8c7fa` (buttons `#a8c7fa` on `#062e6f`), warning chips `#f2b8b5`, round icon tiles, 18 px card radius, big clock-less header. Landscape, 16:9, full-screen layer like the lots, not a phone frame. Navigation: every tile and row is a `bng-nav-item` (the phone's `navify`, `slPhone.js:923`), d-pad moves, A selects, **B closes** (back one page, then out), `tab_l`/`tab_r` change the car. The stock grouping is kept; the look is ours (no stock assets or icons copied).

```
+------------------------------------------------------------------------------+
|  Commercial Garage                                         $12,400   Day 9   |
|  ( Street kid · 140 rep )                                                [B] |
|                                                                              |
|  --------------------  VEHICLE MANAGEMENT  --------------------------------  |
|  [<]  +----------------------------------------------+  [>]                  |
|       |  Sunburst 2.0 Sport S AWD     in this garage  |                      |
|       |  good · 61,000 km · value $8,900               |                      |
|       +----------------------------------------------+                       |
|   ( Part customization )  ( Tuning )  ( Painting )  ( Repair  $340 )         |
|                                                                              |
|  --------------------  GENERAL  ------------------------------------------  |
|   ( My cars )  ( My parts )  ( Dealers )  ( Bank / insurance )  ( Street cred )|
|                                                                              |
|  (i) Painting: bring the car into the garage first.                          |
+------------------------------------------------------------------------------+
```
Pages behind a tile (all in the same frame, back arrow top left): **Dealers** = list of the six dealers (name, distance, "N cars today"), a dealer shows its cars as cards (picture-less: name, year, mileage, price), Buy then "Delivered to <garage> in ~N h"; **My cars** = the phone's list; **Bank** = the phone's bank page; **Street cred** = the phone's page; **My parts** = shelf list by car. Garage tiles close the laptop and open the Wrench Works garage on that car.

## 5. Build plan (4 tasks)

| task | files (owner) | effort | tests |
|---|---|---|---|
| **L1 menu rules and data** | new `sl/core/laptop.lua` (pure: facility `functions` + career state -> groups, tiles, disabled reasons), `sl/computer.lua` (T13's file: send the state, open/close), data builders reusing `sl/phone.lua` (cars, bank, street cred) | S-M | luatest: each of the five computers gives the right tiles; reasons (no car, in a race, car outside the garage, needs repair); release-2 tiles hidden |
| **L2 UI module** | new `mod/ui/modModules/slLaptop/slLaptop.js` (own file, shared look copied from the phone's tokens, not edited into `slPhone.js`), registered in the mod script | M | `tools/laptoptest.js` in the style of `phonetest.js` (jsdom: tiles, back, nav attributes, disabled text) |
| **L3 dealers and delivery** | new `sl/dealers.lua` (offers per stock dealer: the lot's seed, remote buy, delivery after N hours by `sl_fleet.deliver`), `sl/lot.lua` shares the offer builder | M | luatest: same offers as the lot, price taken once, a delivery arrives after its delay, a car bought remotely is not offered again |
| **L4 garage entry** | WW `slrr/garage.lua`: `enterWith(vehId, mode)` (catalog / tune / paint / repair) from the laptop; SL calls it | S-M (WW repo) | in-game only (`tools/ingame_test.lua` step); luatest for the SL side with a stub |
Order: L1 and L2 together (the screen with My cars, Bank, Street cred, which are all REUSE), then L4 (the garage tiles), then L3 (the marketplace). Only L3 and L4 add behaviour; L1+L2 alone already replaces the phone prompt.

## 6. Risks
- **Garage entry (L4)**: the WW garage is entered by driving or walking into a doorway marker with a car (`garage.lua:1708` `enterNearest`); a button that enters it for a chosen car from a computer is new and must not break the state machine (phases idle/film/garage/catalog/busy). Needs a game turn.
- **Remote purchase (L3)** touches money, fleet and save: a bought car must survive a save/load before delivery (store the order in the career save, `sl/core/state`), and the same offer must not be sold at the lot and the laptop (offer ids are place-prefixed since T12).
- **Two UIs to keep in step** (phone and laptop read the same data): build the data once (L1) and render twice.
- **Stock numbers**: a laptop "market" for 6 dealers with 4-6 cars each is about 30 cars; building them is lazy (data only, built when delivered), not 30 spawns.
- **Positions**: computer positions are scene objects (door areas), so the five prompts depend on `getAverageDoorPositionForFacility` (T13 already handles an empty result).
- **Gamepad**: every control must be a `bng-nav-item`; the B (back) event must close the laptop without reaching the game's pause menu (the phone solves this at `slPhone.js:949`).
- **Not checked**: the stock Vue pages behind the tiles (only the home page was read); whether `permissions` tags exist in our freeroam (we do not load `career_modules_permissions`; our own rules replace them); nothing was run in game.
