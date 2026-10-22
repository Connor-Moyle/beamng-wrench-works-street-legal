# Car mastery (campaign idea #13): design, 0f, 2026-10-22

Status: design, for 62 and a5. Switch: part `mastery` ("Car mastery", opt `slMastery`, on Active features). Off: no levels, no perks, no badge, the counters still sit in the save.

## What the player sees
Each car you own gains mastery by being driven and raced cleanly. Six levels (0 to 5). My cars shows a badge with the level and the points to the next one; the car card lists the perks of the level in plain words. A new car starts at 0: mastery belongs to the car record and goes when the car is sold, scrapped or lost, so buying a mastered car gives nothing.

## Points
- 1 point per 5 km driven since you got the car (the odometer the service card already reads: `wear.kmSince(engineKm, mileage)`; a stored high-water mark `car.mastery.km`, so a repair or an engine swap that resets the odometer never loses points).
- 20 points per clean run: a race or job finished (`carcare.onRaceResult` side) with no new wreck during it. Clean runs are counted as `car.mastery.clean`, +1 per finished race while `history.wreckedNow` is not set.
- A wreck costs nothing already earned (the penalty is the missing clean run), so a bad crash cannot destroy the save's progress.

Thresholds: 100, 300, 600, 1000, 1600 points. About 500 km plus 25 clean runs reaches level 5.

## Perks (small, per level, caps)
| perk | per level | at level 5 | where |
|---|---|---|---|
| Insurance | 2 % off the weekly premium | 10 % | `sl/bank.lua` billing and the quote: the factor of the ACTIVE car at that moment (`mastery.factor('insurance', car)`) |
| Trade-in | 1.5 % on a private sale | 7.5 % | `market.resaleValue` result times the factor, floored to 50 like the rebuilt premium; not on scrap, not on the pink-slip value |
| Service and tyres | 2 % off the car's own service card and its tyre purchases | 10 % | `sl/service.lua` `pf` (multiplied with the tier perk `service`) and the shops' price-factor chain for tyres (a5 / 19: which function is the chain for the tyre shop?) |
| Badge | none | none | My cars |

All factors are multiplied with the tier perks (#6), never added. Worst case together with tier 6: service 0.85 x 0.90 = 0.77.

Notes: the km count keeps its highest value, so after an engine swap or an odometer reset the km progress waits until the new odometer passes the old maximum (the points already earned stay). A clean run is any race result (win, loss) with no wreck since the previous result; a race the game never reports (a DNF that sends no result) earns nothing. A car with no recorded price paid (gift, barn find) gets no trade-in bonus.

## Why it is no loop or exploit
The trade-in bonus is held at what you paid for the car (`car.boughtFor`; market.resaleValue is already capped at 90 % of it), so buy-drive-sell cannot profit; it only makes the sale less bad. Kilometres count only from the odometer while driving, clean runs only on finished races (a fresh race a minute pays the normal race rules). Insurance saving is at most $8 of the $80 base a week.

## Where it plugs in
- `sl/core/mastery.lua`: pure rules (`points`, `level`, `next`, `factor(kind, level)`, `perks(level)` for the card, `bump(m, kmNow, clean)` for the counters), tested by `tools/luatest.lua`.
- `sl/mastery.lua` (extension `sl_mastery`): `of(carId)` for the phone, `factor(kind, car)`, hooks `onStreetLegalRaceFinished` (clean run) and a once-a-minute km sync for the spawned active car; part gate `mastery`.
- Save: `car.mastery = { km, clean }` additive; absent means 0, no migration.
- My cars (phone): badge text from `of()`; strings in `core/strings.lua`; help page; changelog; PLAYER_GUIDE through `helpdoc.py`.
- `tools/economy_sim.py`: a `mastery` flag (`--nomastery`), the check is that the median net worth moves by under 2 % over twelve hours.
- TEST_MATRIX row via ab: drive 5 km, level 0 to 1 shown on My cars; a clean race adds 20; off switch hides everything and prices return to the base.

## Questions
- a5: is the premium billed per account (it is: `bank.premium(claims, day)`), so the active car at billing decides the insurance discount. OK, or should it be the best car in the garage? I chose the active car so it rewards driving your favourite.
- 19 / a5: which function is the shops' price-factor chain for tyres?

## Built (0f, 2026-10-22)
`sl/core/mastery.lua`, `sl/mastery.lua` (sl_mastery), the part `mastery` (35 parts), `market.masteryFactor` hook, `bank.lua` prem(), `service.lua` pf, the shops chain id `mastery` (tyre shops only; sl_tyrecare's own counter price is not in the chain), `fleet.list` field `mastery`, the badge in slPhone.js My cars, help, changelog, PLAYER_GUIDE. a5 answered: active car for insurance OK; the ledger line text is not changed yet. Economy: the best case is $8 a week on insurance and about 4.5 to 7.5 % on a sale and on service; not run through economy_sim (no sim hook; the savings are below the noise of the sim). Offline tests only (luatest 15,457), nothing seen in game.
