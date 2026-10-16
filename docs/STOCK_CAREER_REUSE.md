# Stock BeamNG 0.39 career pieces: what Street Legal can reuse on West Coast USA (T2)

Worker A, 2026-10-16. Read-only static study; nothing was run in game. Game Lua root: `I:\SteamLibrary\steamapps\common\BeamNG.drive\lua\ge\extensions` (written `ge/` below). Level data: `content/levels/west_coast_usa.zip`, `levels/west_coast_usa/facilities/`. SL = `mod/lua/ge/extensions/sl/`. Not read: the Vue/ui files behind `career.computer` (not in `lua/`), and the stock career's `onUpdate` loops beyond what is cited.

## 1. The finding that decides everything

Every stock career module is an extension that is **only loaded while the stock career is active**:

- `career/career.lua:244-299` `activateCareer` sets `careerActive = true`, **removes all vehicles** (`core_vehicles.removeAll()`, :290), loads the level, and calls `toggleCareerModules(true)` (:172-206). That loads *every* file in `ge/extensions/career/modules/` (all 40+ modules and the 13 `delivery/` files) and calls each module's `onCareerActivated` (:201-204).
- `career.lua:36-38` then blocks input actions (vehicle switching, teleporting, `aiControls`, `funStuff`, ...), and the save lives in the stock `career_saveSystem` profile (not `/settings/street_legal/`).
- Modules guard themselves: `vehicleShopping.lua:1020` and `inventory.lua:55` do `if not career_career.isActive() then return false end` in `onExtensionLoaded`, which refuses to load the module.
- `career_career.levelName = "west_coast_usa"` (`career.lua:21`): the stock career is built for this very map, so every stock piece fits WCUSA data-wise. The blocker is not the map, it is that the pieces assume the stock career's wallet, inventory, save and UI.

SL is a freeroam career with its own wallet (`sl/career.lua:222-238`), fleet (`sl/fleet.lua`), lots (`sl/lot.lua`), job board (`sl/jobs.lua`), phone (`sl/phone.lua`) and save (`career.lua:22-27`). Running the stock career next to it would mean two wallets, two car inventories and two save systems, and `activateCareer` deletes SL's cars on entry. So **the stock modules cannot be switched on as they are**. What is reusable is (a) the level's facility data and the `freeroam_*` APIs that work without a career, (b) a few career-independent helper modules, and (c) patterns to copy.

## 2. What works with no career at all

| piece | evidence | already used by SL |
|---|---|---|
| `freeroam_facilities.getFacilities(level)` / `getFacility` / `getFacilitiesByType` | `ge/freeroam/facilities.lua:78-128`: reads the level's `info.json` and every `*.facilities.json`; no career reference | yes: `sl/jobs.lua:87`, `sl/classifieds.lua:517` |
| `getAverageDoorPositionForFacility`, `getZonesForFacility`, `getParkingSpotsForFacility`, `getGaragePosRot`, `teleportToGarage` | `facilities.lua:135, 214, 179, 248, 260`: resolve a facility's doors (scene objects) and its `sitesFile` parking spots | no |
| `freeroam_gasStations.gasStationCenterRadius` | `ge/freeroam/gasStations.lua:30,51` | yes: `jobs.lua:89`, `station.lua:85` |
| Alder drag strip POIs | `facilities.lua:476-478`: `dragstrips` are emitted for **any** mode; only dealerships and computers are gated by `career_career.isActive()` (:463) | no |
| `util_configListGenerator` (`getEligibleVehicles` :175, `getRandomVehicleInfos` :195, `doesVehiclePassFilter` :70) | `ge/util/configListGenerator.lua`: 231 lines, no `career_` reference at all | no (SL has its own `carBuilder.configs`, `carBuilder.lua:22`) |

Two consequences: the stock walking markers for dealerships and computers do not appear without the stock career (`facilities.lua:463-473`), so SL must supply its own trigger (it already does: `lot.lua:430` `onActivityAcceptGatherData` for `slrrPlace`). And facility positions are **scene-object names, not coordinates** (`doors: [["belascoAuto_area_1","belascoAuto_icon_1",30]]`), so the T6 CSV (`audits/wcusa_facilities.csv`, 409 rows) holds only the delivery sites' parking spots and the two `*.race.json` path nodes. It has **no dealership, garage, computer or gas-station positions**. Those must be read in game (`getAverageDoorPositionForFacility`) or from the level's scene (not extracted).

## 3. The level's facilities (from the zip)

- **Dealerships** (`dealerships.facilities.json`, six entries): `belascoAuto`, `jeffersonmotors`, `richsmotorcompany`, `quarrysideAutoSales` (door `garageDealership_area_1`), `truckShop` (`commercialVehicleSales`), and `apmStarterVehicles` (no doors, no parking: the tutorial's starter-car seller, not a place). Each carries `filter`/`subFilters` (year, mileage, value, region, config type), `fees` (749 for Belasco), `discountChances`, `testDrive` (abandon fee 100, 120 s), `parkingSpotNames`. SL's `west_coast_usa.json` places already name the dealer "Jefferson Motors" (= `jeffersonmotors`), the junkyard and the scrapyard.
- **Garages** (`facilities.facilities.json`): `servicestationGarage`, `commercialGarage`, `alderDragwayGarage`. **Computers**: `servicestationGarageComputer`, `servicestationOfficeComputer`, `commercialGarageComputer`, `commercialGarageComputer2`, `alderDragwayGarageComputer`. **Gas stations**: 10 (5 sites, each with a KEVee charger twin).
- **Delivery** (`facilities/delivery/*.facilities.json` + `*.sites.json`): fuelStations, mechanics, mixed, offices, residential, restaurants, shops, warehouses, with previews. In the CSV: parkingSpots 5 + 29 + 66 + 220 + 5 + 37 = 362, plus residential `top`/`bot` 14, plus 33 race path nodes.

## 4. Piece by piece

### 4.1 Dealerships and vehicle shopping (`career/modules/vehicleShopping.lua`, 1161 lines)

- **Does**: builds a rolling stock of cars per seller (`updateVehicleList` :257, using the level's dealership filters via `util_configListGenerator` :329-374), shows them in a Vue shop, negotiates, spawns and sells (`spawnVehicle` :508, `buyVehicleAndSendToGarage` :581, `buyVehicleAndSpawnInParkingSpot` :596).
- **Entry**: `openShop(seller, originComputerId, tag)` :615 (navigates `career.computer.vehicleShopping[.vehicles]` :640-644); computer entry via `onComputerAddFunctions` :1059.
- **Outside career?** No. `M.dependencies = {'career_career','util_configListGenerator'}` (:7); `onExtensionLoaded` returns false when inactive (:1020); `career_saveSystem` for `vehicleShop.json` (:1025, :1052); money through `career_modules_playerAttributes.addAttributes` (:566, :955); the new car goes to `career_modules_inventory.addVehicle` (:526, :754); also `quickTravel.getPriceForQuickTravel` (in `openShop`, :623-636), `hasBoughtStarterVehicle` (:587, :834), `tether`, `gameplay_achievement`.
- **SL already has this job**: `lot.lua` (browse, test drive, buy, sell on a display spot, `lot.lua:294-376`) fed by `sl/core/market` and `carBuilder.configs`.
- **Risks**: save format version `moduleVersion = 61` (:9) changes between BeamNG updates; the Vue routes are internal. Wrapping it means faking `playerAttributes`, `inventory` and a profile.
- **Effort**: WRAP the whole module = L and fragile. Reusing only the data = S.
- **Recommendation: SKIP the module. REUSE the data**: (1) add the four other dealers as SL `places` (kind `dealer`) from the stock doors (S; one `dealer` place exists, `places/west_coast_usa.json`); (2) optional later: feed `lot.lua` offers from `util_configListGenerator.getRandomVehicleInfos(dealership, n, ...)` so each dealership sells its own stock (M; pass the facility's `filter`; SL keeps its `carBuilder` spawn and its own wallet).

### 4.2 Computer / laptop menu (`career/modules/computer.lua`, 130 lines)

- **Does**: a menu opened at a computer facility. It lists the cars in the closest garage (`inventory.getInventoryIdsInClosestGarage` :24, `insurance.inventoryVehNeedsRepair` :29), then **broadcasts `onComputerAddFunctions`** (:41) so other career modules add their buttons (vehicle shop `vehicleShopping.lua:1059`, part shopping, tuning, painting, inventory `inventory.lua:1397`). The menu itself holds no features.
- **Entry**: `openMenu(facility)` :18, `openComputerMenuById(id)` :103 (= `getFacility("computer", id)`), UI via `ui_router.navigate("career.computer")` :53, button routing `computerButtonCallback` :57, data `getComputerUIData` :68.
- **Outside career?** No: `M.dependencies = {"career_career"}` (:7), calls `career_modules_inventory`, `insurance`, `tether`, `hasBoughtStarterVehicle` (:39) unguarded, so it errors if those are not loaded.
- **How SL would use it**: SL does not need the menu; it needs a *trigger at the five computer doors* that opens its own screen (the phone, or a laptop view of the same apps). The mechanism to copy is the one SL already uses for lots: `onActivityAcceptGatherData` (`lot.lua:430`) adding a prompt button; for a position use `freeroam_facilities.getAverageDoorPositionForFacility` (:135) of `getFacilitiesByType('computer')`.
- **Effort**: S (a prompt at each computer that opens `sl_phone`) to M (a laptop-styled screen). **Risk**: none for saves; the computer ids and door objects are map data and stable.
- **Recommendation: SKIP the stock module, COPY-ADAPT the idea**: the computers become SL "laptop" entry points.

### 4.3 Delivery / cargo (`career/modules/delivery/*.lua`, 13 files, about 8,900 lines)

- **Does**: a full logistics game: facilities offer parcels and vehicle jobs (`generator.lua` 1515, `parcelManager.lua` 696, `vehicleOfferManager.lua` 404, `vehicleTasks.lua` 701), a cargo screen on the big map (`cargoScreen.lua` 1840), progress and rewards (`progress.lua` 632), a delivery mode that locks selling, storage and shopping (`general.lua:876-` `deliveryActivity`, `startDeliveryMode` :1021, `isDeliveryModeActive` :1024).
- **Outside career?** Only on paper: its declared dependency is `core_vehicleBridge` (`general.lua:6`), but the aliases `dGeneral`, `dProgress`, `dParcelManager`... are set only in `onCareerActivated` (`general.lua:10-21`), which only `toggleCareerModules` calls (`career.lua:201-204`). Without it, every cross-module call hits a nil local. Save goes through `career_saveSystem` (`general.lua:38, 150`). Rewards go through `playerAttributes`, `career_branches` and `career_modules_branches_landing` (`progress.lua:418-432`, `cargoScreen.lua:978-990`) and autosave (`progress.lua:513-514`). It is also wired into stock UI outside `career/`: `freeroam/bigMapMode.lua:1053,1072`, `bigMapPoiProvider.lua:633,688`, `career.lua:712`, `uiUtils.lua:65`.
- **Data side is clean**: the facility files carry logistic types, `sitesFile`, previews, and `gameplay_sites_sitesManager.loadSites` (`generator.lua:1259-1263`) works without a career.
- **Risks**: `moduleVersion = 42` (`general.lua:7`); a big surface that any BeamNG update can change; too big to fork and maintain.
- **Effort**: WRAP = L (stubbing `playerAttributes`, branches, saveSystem, big-map hooks for ~9k lines). COPY the data = M.
- **Recommendation: SKIP the engine. COPY-ADAPT the places**: use the stock delivery facilities (names, previews, the parking spots from the `*.sites.json`, the 362 spots in the CSV) as pickup and drop-off places in `sl_jobs`. Today courier/part/food jobs take legs from SL places, shops, diners and random kerbs (`jobs.lua:112-135`, `diners()` :85-93); stock businesses and their parking spots give WCUSA real destinations (a warehouse, a restaurant, a mechanic) with pay and cargo kept in SL's own rules (`sl/core/jobs`, `finishWith`, one money path). M, no stock save involved.

### 4.4 Garages and inventory (`career/modules/inventory.lua`, 1428 lines)

- **Does**: the stock car list (`addVehicle` :299, `getVehicles`, `enterVehicle`, `sellVehicle`), the garage UI, parts condition, spawning cars back at the closest garage (`getClosestGarage` :36 from `facilities.garages` zones, `teleportToGarage` :571).
- **Outside career?** No: `M.dependencies = {'career_career', "career_modules_log", "gameplay_tutorial_setup"}` (:7), `onExtensionLoaded` returns false when inactive (:55), `career_saveSystem` profile (:57), 21 `career_career`/`career_saveSystem` uses. The shopping, computer, delivery and test-drive modules all call it, so it is the keystone that cannot be faked cheaply.
- **SL already has this job**: `sl_fleet` (cars as save records, spawned on demand, `fleet.lua:1-6`) plus the Wrench Works garage (`slrr/garageSites`, `fleet.lua:46-62`).
- **Usable parts**: the three garage facilities as places and parking: `getParkingSpotsForFacility` (:179), `teleportToGarage` (:260, needs only `spawn`/`core_camera`, no career). I did not check whether SL wants the stock garages or only Wrench Works' own; W3 (`progression.garages`) decides.
- **Effort**: SKIP inventory. Garage places S.
- **Recommendation: SKIP.**

### 4.5 Smaller pieces

| piece | verdict | why |
|---|---|---|
| Gas stations and fuel (`freeroam_gasStations`; `career/modules/fuel.lua` needs `career_career` :7) | REUSE the freeroam side (already done) | `fuel.lua` only adds career billing |
| Test drive / inspect (`testDrive.lua`, `inspectVehicle.lua`; deps `{}` but `career_modules_payment.pay` :204, `career_career.setAutosaveEnabled` :114) | SKIP | SL's `lot.lua` test drive exists (`lot.lua:333-374`); the dealership `testDrive` fees are only data |
| Alder drag strip (`freeroam_dragRace`, facilities `dragstrips`) | REUSE as is | emitted without a career (`facilities.lua:476-478`); SL has `kind='drag'` races (`races.lua`); S to pay out via `onSlrrRaceFinished` |
| Vehicle value (`valueCalculator.lua`, deps `career_career` :7, needs `partInventory`) | SKIP | SL has `sl/core/market`, `carBuilder.partsValue` (:111) |
| Quick travel, insurance, loaner vehicles, milestones, branches (skills) | SKIP | all read `playerAttributes` or the profile; SL has the cab (`cab.lua`), bank and insurance (`bank.lua`), achievements |

## 5. Summary table

| piece | runs outside career? | how SL calls it | effort | risk | verdict |
|---|---|---|---|---|---|
| Facility data and `freeroam_facilities` API | yes | direct calls (as `jobs.lua:87`) | S | low: stable API, map data | **REUSE** |
| Stock dealerships (5 real + 1 tutorial) | data yes, module no | places from doors; optional `configListGenerator` stock per dealer | S / M | low (data); `vehicleShopping` save v61 if wrapped | **REUSE data, SKIP module** |
| `util_configListGenerator` | yes | `getRandomVehicleInfos(dealerFacility, n, eligible, 'adjustedPopulation')` | S-M | low-medium: filter keys follow BeamNG's attribute names | **REUSE (optional)** |
| Computer menu | no | own prompt at computer doors opens `sl_phone` | S-M | low | **COPY-ADAPT the idea** |
| Delivery engine | no (nil aliases) | none | L | high: churn, 8.9k lines, big-map hooks | **SKIP** |
| Delivery facilities and sites | yes | pickup/drop-off places for `sl_jobs` | M | low-medium: site format | **COPY-ADAPT data** |
| Garage and inventory | no | none (`sl_fleet` stays) | L | high | **SKIP** |
| Garage and parking facility helpers | yes | `teleportToGarage`, `getParkingSpotsForFacility` | S | low | **REUSE if wanted** |
| Gas stations, drag strip | yes | already used / marker as is | none / S | low | **REUSE** |

## 6. Best combined approach for release 1

Run **no stock career module** and keep SL's wallet, fleet, lots, phone and save as the one source of truth, because the stock modules only load under `activateCareer`, which wipes the player's cars, blocks input and brings its own economy and save (`career.lua:244-299`). Instead make WCUSA feel like the stock career by **reading its map data through `freeroam_facilities`**, which works in plain freeroam and which SL already calls. Concretely, in this order: (1) S: turn the stock dealerships (`belascoAuto`, `jeffersonmotors`, `richsmotorcompany`, `quarrysideAutoSales`, `truckShop`) and the three garages into SL `places` by resolving their doors with `getAverageDoorPositionForFacility` in game (the T6 CSV does not contain them), so `lot.lua` shows a car lot at each with the existing browse, test-drive, buy and sell flow; (2) S: put a "laptop" prompt at the five stock computers that opens `sl_phone`, using the `onActivityAcceptGatherData` pattern of `lot.lua:430`; (3) M, optional and after the first QA round: feed `sl_jobs` courier and part runs from the delivery facilities and their parking spots (362 in the CSV) so jobs go to real WCUSA businesses, and give each dealership its own stock through `util_configListGenerator` with the facility's `filter`. Leave delivery, inventory, vehicle shopping, test drive and the stock computer UI alone: they cannot run without the stock career, a wrapper would be larger than SL's own versions, and every BeamNG update (`moduleVersion` 61 for the shop, 42 for delivery) could break it. The cost of this plan is that SL's shops will not look like the stock Vue shop, and delivery will be SL's simpler job board, not the stock cargo screen. Both match the "no new features" directive: item 1 and 2 add map entry points only, and item 3 is deferred until the manager decides F5/F7/F8.

## 7. Not checked

Nothing here was run in game. Not verified: that all five stock dealership door objects exist in the loaded WCUSA scene as named; the `ui` Vue files behind `career.computer`; whether `util_configListGenerator.getRandomVehicleInfos` returns configs that `carBuilder.spawn` accepts without conversion; and whether stock `freeroam_facilities.getZonesForFacility` works with no career (it only needs `gameplay_sites_sitesManager`, :214).
