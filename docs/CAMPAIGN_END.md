# Campaign end check (tier 1 to the last boss)

Walked offline by `tools/luatest.lua` ("the campaign end": a player who wins every race he is offered, at night, racing the best racer he may race and knows).
Run `SL_CAMPAIGN_REPORT=1 node tools/luatest.js` to print the milestones.

## Result (all races won)

- 26 races from nothing to the last boss (bosses fall at races 4, 7, 11, 18 and 26, at rep 341, 562, 1226, 2623 and 4589); 6 more at the top reach rep 6000.
- Every tier has the boss and at least three other racers to beat before him (36 racers, 5 tiers).

## Dead-ends found and fixed

1. **A boss never asked for a player who raced the tier above.** The call needed 3 wins over racers of the boss's own tier, but a player may race one tier up and a greedy player (the simulation) never got the 3. Now wins over the boss's tier or any higher one count.
2. **A showdown could be refused for being poor.** The challenge was made as 'high' (three times a bet), and the racer's answer needs that money in hand. Showdowns are now arranged as a plain race with the showdown stake set afterwards.
3. **A pink slip offer could be refused as "not tonight" / "I don't race for pinks"** after the player accepted it. A rival with an open offer is now always up for it (roster.pinkForced, racer.pinkOK), and the offer is never turned into a race by the rival himself; the player accepts naming the car, races for money instead, or walks away.
4. **An old save would have been locked out of races it could already do.** A save without rivals starts at the rank its rep has reached (the bosses of the tiers below count as beaten).
5. **West Coast USA has no Race of Champions** (progression.MAPS west_coast_usa has no `roc`), so its campaign had no end. Beating the last boss now ends it: a text from Benny and the achievement "Top of the strip"; the street goes on.

## Cannot be checked offline (needs the game)

- WCUSA's race start lines (sl_races) enough to give each tier a race, and the three garages (alderDragwayGarage, commercialGarage, belascoCityGarage) all being in the level.
- The rep needed for garage 3 (1000) and the ROC entry (50000) are irrelevant to the WCUSA end, but the achievements "Top floor" and "Six figures" still need them.
- Whether the tier-5 pink showdown flow (offer, accept, the race, the car moved) works end to end: steps for connor-80.
