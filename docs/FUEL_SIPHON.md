# Fuel siphoning (design, 0f, 2026-10-22)

Connor: "add stealing fuel from cars, but the player must have a jerry can and a syphon tube". Status: design note for 62, ba (fuel and range, the can), 19 (inventory), ab (fair game, witnesses, heat) and a5 (career). Nothing built, nothing run in a game. The sections below say what the game lets us read and write for another car's fuel, then how the feature uses it.

## 1. What the game lets us read and write (from the game's Lua, 0.40)
Fuel is an energy storage (`lua/vehicle/energyStorage/fuelTank.lua`) in the car's own VM. The game side reaches it through the gameplay interface (`lua/vehicle/extensions/gameplayInterfaceModules/interactEnergyStorage.lua`):

- **Read**: `core_vehicleBridge.requestValue(veh, function(ret) ... end, 'energyStorage')` gives `ret[1]` = a list of tanks `{ name, storageType, energyType, currentEnergy, maxEnergy }` (joules). A callback, not a return value (one round trip to the car's VM). The career fuel module, the gas stations and the flowgraph fuel nodes all use exactly this call, on the player's car; it is keyed by the vehicle object, so the same call is expected to work on any spawned car whose VM has the interface (parked, lot, traffic). **To verify in the game (80): it answers for a parked and for a traffic car.**
- **Write**: `core_vehicleBridge.executeAction(veh, 'setEnergyStorageEnergy', tankName, joules)` sets `storage.storedEnergy` directly (no clamp: we clamp to 0..maxEnergy ourselves). The tank's own `updateGFX` then recomputes the remaining volume and the fuel's mass on the tank nodes, so the car gets lighter as it is drained. This is what the gas stations use to fill a tank.
- **Units**: litres = joules / (fuelLiquidDensity x energyDensity): gasoline 0.75 kg/L x 41.5 MJ/kg = 31.125 MJ/L, diesel 0.84 x 43 = 36.12 MJ/L, kerosene 0.80 x 43 = 34.4 MJ/L. The tank's capacity in litres is `maxEnergy` over the same factor. Only `energyType` gasoline / diesel / kerosene tanks of type `fuelTank` are siphonable (never `electricBattery`, nitrous or pressure tanks).
- **Leaks**: a broken tank leaks by itself (`currentLeakRate`); we do not touch it.
- **Not possible**: pulling fuel from a car that is not spawned (a car in the lot's catalogue or off the map has no tank to read); the game has no siphon, no cap, no alarm and no owner reaction of its own, so those are ours.

## 2. What the player does
1. Needs BOTH a jerry can (an inventory item `can` with `litres`, `size`, `fuel`) and a siphon tube (`tool` id `siphon_tube`) in the inventory (19's inventory, docs/INVENTORY.md); either missing: a short text says which ("You need a siphon tube").
2. Walks up to a car (within 2.5 m of its rear or fuel flap) on foot, with the can in the inventory: a prompt "Siphon fuel (Hold)". The prompt only shows for a parked or stopped car with fuel of a fuel type the can can take.
3. Holds to siphon: the litres move at the siphon rate (default 0.25 L/s: a 10 L can in 40 s, a 20 L can in 80 s) from the car's tank into the can in steps (the can's litres and the car's `setEnergyStorageEnergy` change together every second). Stops when the can is full, the tank is at 2 %, the player lets go, walks more than 4 m away, enters a car, or the car is driven off / hit by something.
4. Pours the can into their own car (a prompt at their own car's fuel flap, "Pour fuel"): the same call the other way, through ba's fuel and range work (the toast and the range readout follow); partial pours keep the rest in the can. A can can also be poured into another can later (19's inventory).
5. Fuel types: a can holds one type (the first fill sets it, empty again resets it); pouring diesel into a petrol tank is refused with a text (the game refuses nothing, so we do), siphoning a different type into a non-empty can is refused.

## 3. Rules (pure, `sl/core/siphon.lua`, tested by tools/luatest.js)
- Conversions above; `fuelOf(tank)` returns type and litres or nil for a non-fuel tank.
- `step(can, tank, dt, rate)`: how many litres move this step, bounded by the rate, the can's room, the tank's level over the 2 % floor, and the can's fuel type; returns the new litres of each, never negative, never over capacity.
- `canPour(can, tank)`: type match, room in the tank.
- `interrupted(state)`: released, distance over 4 m, in a car, car speed over 1 m/s, the tank gone.
- Risk (section 4) as a number per 10 seconds.

## 4. Fair game, witnesses, heat (ab's rules; interfaces to agree)
Taking fuel from other people's cars is a crime in the world the career plays in.
- **Own cars** (any car in the player's garage list): free, no risk, no rep; just the can.
- **Parked or lot cars and traffic that has stopped**: risk per 10 seconds of siphoning = `siphonRisk` x base (0.10 at night, 0.25 by day) x witnesses (1 + 0.5 per pedestrian-like witness within 25 m, from ab's witness query), x 2 within sight of a police unit. A noticed siphon: the player gets heat (like a street race, `heat.RACE`-sized), a fine or a rep loss (a5's ledger), the owner of a traffic car honks and drives off (no violence; a tow/impound is not triggered by siphoning alone).
- **ab's theft rules (sl_theft, branch theft):** when the Car theft part answers, `sl_theft.fairGame(vid)` decides whether a car may be touched ('own' = not for taking, 'running' = moving: both refused) and `sl_theft.exposure(vid, noise)` is asked every ten seconds of siphoning (noise = the siphon noise setting): a witness or the alarm stops the siphon, the heat and the alarm are theirs. nil (part off, no theft branch) means the rules here.
- **Current limit (without them):** until ab's witness query exists, passing moving cars within 25 m x the noise setting are the only witnesses; a car with a police car in sight is the same risk as a lonely one. `slSiphonRisk` is the player's lever.
- Interfaces needed from ab: `sl_crime.witnesses(pos, radius)` (count and police yes/no) or the existing heat/phase helpers, and a way to add heat and a record ("fuel theft") to the rap sheet (idea #7). Until ab's rules exist the fallback is the police-within-60 m rule only.
- Nothing ever hurts the player physically.

## 5. Settings (Mods menu > Street Legal > Parts of the game > Fuel siphoning; every row tagged "gameplay" for ba's presets)
- `slSiphon` (part switch, **OFF by default**: needs the Inventory part; off = no prompt, nothing moves).
- `siphonRate` (L/s, 0.05 to 1, default 0.25).
- `siphonNoise` (0 to 1: how likely the siphon is heard by passers-by, default 0.5; feeds the witness count).
- `siphonRisk` (0 to 3x, default 1).
- `siphonOwnCars` (own cars always free, default on).

## 6. Where it plugs in
- `sl/core/siphon.lua` (pure), `sl/siphon.lua` (extension `sl_siphon`: finds the target car near the walking player, the prompt, the held siphon, the guarded `core_vehicleBridge` calls and the inventory calls), part `siphon` in core/features.lua, strings, help, changelog, a TEST_MATRIX row via ab.
- **Inventory** (19): `sl_inventory.count(kind, id)` / `sl_inventory.items('can')` and `.setCanLitres(item, litres, fuel)`; if the module or the part is missing the feature is off.
- **Fuel and range** (ba): the pour calls ba's refuel hook so the range readout updates; ba tells us the call.
- **Economy**: a 10 L can of Regular is worth about $14.5 at the pump (sl_carcare FUELS 1.45 per litre); the siphon is for people with no money or a long way from a pump, not an income (tools/economy_sim.py: fuel theft as a weekly action only if it ever shows in the numbers; the risk makes it worse than a job per minute).
- Save: nothing beyond the inventory's can litres; no counters.

## 7. Tests
Pure: the conversions, step bounds (rate, room, floor, type), pour rules, interruption, risk multipliers, garbage inputs. Game side with stubs (`core_vehicleBridge`, `sl_inventory`): both tools required, the can fills and the tank falls by the same energy, an interruption stops it, the pour reverses it, the part off does nothing.

## 8. Questions
- 80 (game): does `core_vehicleBridge.requestValue(veh, ..., 'energyStorage')` answer for a parked car and for a traffic car, and does `setEnergyStorageEnergy` drain it (and does an AI car with an empty tank stop)?
- 19: the inventory calls above, and the item ids (`can`, `siphon_tube`) and fields.
- ab: the witness query and the crime record; whether siphoning shows on the rap sheet.
- ba: the pour hook into the fuel and range module.
