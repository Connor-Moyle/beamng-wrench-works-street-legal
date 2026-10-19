# Switching off the core parts (a note first, nothing built yet)

Written for the review of the "each part optional" work. The fourteen self-contained parts (spectators, billboards, ambience, puddles, achievements, tutorial, markets, rally, races and drag, clubs, crews, tow, cab, jobs) are built: an off part's hooks do nothing, its phone app goes, saves are never touched. These five are tied into more of the game, so here is what the player would get with each off, and what I would do. I will build none of them until this is read.

Rule for all five (the same as the built parts): the save keeps everything; a switch only stops the part acting and hides its screens and markers. Switched on again, it carries on from the save.

## 1. Bank (loan and insurance)
- Off: no Bank app, no loan, no insurance. A loan that is already open stops charging its weekly payment and cannot be repossessed while the bank is off (the debt stays in the save and resumes when it is switched on). Repair and impound bills are paid in full (no insurance share).
- Touches: `sl_bank` hooks (new day), `phone.bank` summary, the repair and impound price paths that ask for the insurance share. One question: a player with an open loan who switches the bank off keeps the borrowed money (nothing is taken back). Is that acceptable, or should the switch refuse while a loan is open? My suggestion: refuse with a line ("pay back the loan first"), because the alternative is free money.

## 2. Hospital (injuries and death at the wheel)
- Off: a crash that knocks out or kills the driver costs nothing and sends nobody anywhere: the car is as it was, the player carries on. No doctor's bill, no "no racing while injured", no game over in a hardcore career (hardcore death is a hospital feature, so with it off hardcore only keeps its no-pull-out rule). The Driver Injuries mod (slrrInjury) can still hurt the driver visually; Street Legal just ignores it.
- Touches: `sl_hospital` (onSlrrDriverInjured/Died), `canDrive()` used by jobs and races, hardcore's death.
- Question: should "hospital off" also switch Driver Injuries off? They are separate mods (Injury is on the Active features page by itself), so I would leave them separate.

## 3. Phone and laptop
- The phone is how the career is played (every app, the jobs, calls, the HUD pill). Off: the career still runs, but the player has no phone screen: no apps, no messages, no pill; calls and texts arrive only as the game's own toasts. Most of the career needs the phone (jobs, races, the garage app), so this is really "the career without its UI".
- The laptop (stock computer facilities): off, the laptop prompt does not show and the facilities stay as the game's own.
- My suggestion: do not offer a phone off-switch. Offer only "HUD phone pill" (the pill and heads-up texts) and "Laptop" as switches, and keep the phone itself always available, since without it there is no way to reach most of the other parts' screens.

## 4. Maps
- Off: no Map app on the phone, no HUD map app data (the feed stops, which also saves its small cost), no route flares from the phone's map (the phone's "route to" actions still set the in-game route line). Nothing else depends on it.
- Touches: `sl_mapsfeed`, the phone's Map tab, the HUD app. Cheap and safe; I would build it with the others.

## 5. House upgrades (garage tools bought in the career)
- Off: the garage has all its tools (lift, bench, dyno, paint booth, shelving, photo corner) from the start, as it does outside a career today; no upgrade shop, no upgrade prices. Already-bought upgrades are irrelevant (all are available).
- Touches: `sl_upgrades` summary and `buy`, and the call that tells Wrench Works what the garage has. This removes a money sink and a progression step, so it makes the career easier; that is the point of the switch.

## What I need from you
1. Bank: refuse the switch while a loan is open (my suggestion), or let it go and keep the money?
2. Hospital off: ignore injuries entirely (as above)?
3. Phone: agree to "no phone off-switch, only HUD pill and laptop"?
4. Maps and house upgrades: go ahead?
