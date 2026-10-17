# Day job variety (design note)

All of it rides on the existing job board (`sl/jobs.lua`: a job is a list of legs, clock from the first stop, pay settled at the last, docked for lateness and damage). No new UI: the phone board shows `title`, `item`, `fragile`.

| Job | Kind | How it works |
|---|---|---|
| Tow job (rep 300) | `tow` | A dead car (engine torque 0, one tyre flat) appears at a city kerb when you arrive. You hook it to your own car with the game's tow coupler and tow it to a garage 600 m+ away. Position, speed and damage are the **towed car's**; you stay in your own car. Time limit is slow (6 m/s). |
| Parts run (rep 0) | `scrapparts` | Scrapyard or a Wrench Works shop to a club garage at least 1.2 km away; always fragile (over 5 % damage pays nothing), 1.5x fragile pay. |
| Taxi fare | `taxi` (existing) | A walker (slrrPedestrians actor) waits at the first kerb and is removed when you pull up. During the ride the player car's velocity is sampled at 10 Hz; a push over 4 m/s^2 (about 0.4 g) counts as a bump. Score = share of the ride without bumps; tip +50 % at 0.9+, +25 % at 0.7+, +10 % at 0.5+ (`core/jobs.lua` comfort functions). |
| Dealer delivery (rep 200) | `dealerdrive` | A new car from the dealer to a customer's kerb 0.8-3 km away. Car Surface FX's scratch level is read at pickup and at the end; any new scratch is the same as a wrecked load (pays nothing), as is a dent. Without Car Surface FX only the damage check applies. |

Open points (game test): the tow coupler must exist on the player's car (the pickup and trucks have one; a car with none cannot do the job: the hook-up hint says so); the dead car must be released from its handbrake; the walker actor needs an installed Drivers mod (without it the fare has no walker, nothing else changes).
Pay balance: tow ~$260 + $200/km, dealer $350 + $130/km, parts run 1.5x fragile rate, all times 1.35 (day jobs); `economy_sim.py` has no rows for them yet.
