# Tunables of Street Legal (the Mods menu, ESC > Mods)

All settings live only in the Mods menu. An entry in `sl/options.lua` M.defs with `tab` and `group` appears there (connor-9e's generator); `advanced = true` hides the expert ones.
Anything that sets a constant of the rules is applied by `sl/balance.lua` (a map of option key -> core module field, read at the moment the rule is used); the rivals' and auctions' numbers are read by `sl/tuning.lua`.

## In the menu now

| Tab | Group | Setting (key) | Default | Range |
|---|---|---|---|---|
| Economy | Jobs | Job pay per km (slPayPerKm) | 140 | 60-300 |
| Economy | Jobs | Day job pay multiplier (slDayJobPay) | 1.35 | 0.5-3 |
| Economy | Jobs | Time allowed on jobs (slJobSlack, advanced) | 1.35 | 1-2.5 |
| Economy | Bank | Loan interest per day (slLoanInterest) | 3 % | 0-10 % |
| Economy | Bank | Biggest loan (slLoanMax, advanced) | 120000 | 20000-300000 |
| Economy | Bank | Insurance deductible / cover (slInsDeductible, slInsCover) | 200 / 50 % | 0-1000 / 10-100 % |
| Economy | Markets | Seller fee (slListingFee) | 5 % | 0-20 % |
| Economy | Services | Car wash price (slWashPrice) | 15 | 0-100 |
| Economy | New careers | Starting money (slStartMoney) | 5000 | 1000-20000 |
| Police & heat | What raises/lowers heat | Race, near miss, bust, escape, cooling (slHeatRace, slHeatNearMiss, slHeatBust, slHeatEscape, slHeatCool) | .12 / .04 / .2 / .06 / .01 | see options.lua |
| Races | Racers | Pink slip nights, rematch texts, taunts (slPinkChance, slRematchChance, slTauntChance) | 12 % / 50 % / 40 % | 0-50 % / 0-100 % / 0-100 % |
| World | Performance | Seconds between built cars (slBuildGap, advanced) | 20 | 8-60 |
| Rivals / The climb / Car auctions | | 15 entries (see sl/options.lua) | | |
| (existing) | | Police, Police aggression, Pay (slEconomy), Hardcore, Crew raids, Traffic in street races, Race flares, Text pop-ups, Clock speed, Dashboard, Record races, Text size, Colour blind, Captions, Performance overlay, Wallpaper, Auto photo, Weather, Rain | | sl_options (connor-9e moves them) |

## Worth exposing, still local constants (owner to change; each needs `sl_options.get(key)` in place of the constant)

| Where | Constant | Default | Proposed setting (plain label) | Range | Owner |
|---|---|---|---|---|---|
| police.lua | PATROLS | 2 | Patrols at night (ambient) | 0-4 | 9e / a5 |
| streets.lua | MAX_CRUISERS | 3 | Racers cruising at night | 0-6 | a5 |
| streets.lua | CITY_RACE | 1800 m | Longest street race | 800-4000 m | a5 |
| streets.lua | RACE_TIMEOUT | 600 s | Time before a race is called off | 240-1200 s | a5 |
| streets.lua | MEET_MIN_DIST | 130 m | Distance before a meet is built | 80-300 m | a5 |
| core/progression.lua raceResult | 35 base rep, x1.5 at night, pink +60 | | Reputation per race | 50-200 % | 9e |
| core/roster.lua TIERS | bet ranges, skill ranges | | Opponent skill (all racers) | 70-130 % | a5 (AI) |
| carcare.lua | CRASH_DAMAGE | 2000 | Damage that counts as a crash | 1000-5000 | 9e |
| core/market.lua | REPAIR_BACK, SELL_BACK, REPAIR_CONDITION | 1.35 / .9 / 3 | Repair cost multiplier, dealer buy-back | | 9e |
| core/weather rules | rain chance (exists: slRain) | | | | |
| fuel use / consumption | the game's own | | not ours | | |
| day/night length | slClock (exists) | | | | |
