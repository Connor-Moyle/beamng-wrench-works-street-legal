"""Economy and progression simulation for Wrench Works: Street Legal (balance pass).

Simulates players through a career in real minutes, choosing sensible things to do (jobs, races,
activities, upgrades) with the career's actual numbers (core/progression.lua, roster.lua, market.lua,
jobs.lua, activities.lua), and reports when money and reputation milestones arrive, the pay per real
minute of every job and activity (to spot exploits), and how police fines land.

  python tools/economy_sim.py            # 200 players, prints the tables
  python tools/economy_sim.py --plot out.png   # also plots money and rep over time (needs matplotlib)

Assumptions (check in game): real minutes per in-game day (DAY_MIN), drive speed in town, and how
often the player wins against each tier with a car of a given class.
"""
import math, os, random, sys, statistics

PLAYERS, HOURS = 45, 12   # simulated players, hours of play each
DAY_PAY = float(os.environ.get('DAY_PAY', '1.35'))     # = core/jobs.lua DAY_PAY
BOOST = '--noboost' not in sys.argv     # the early-game boost in sl_jobs
DAY_MIN = 30.0            # real minutes per in-game day (BeamNG's TimeOfDay dayLength; verify in game)
NIGHT = (20, 5)           # night hours, as progression.isNight
CITY_SPEED = 11.0         # m/s average across town, stops included
START_MONEY = 5000
TIERS = [  # roster.TIERS: rep range, bet range
    dict(rep=(0, 150), bet=(100, 400)), dict(rep=(150, 600), bet=(300, 1000)), dict(rep=(600, 1800), bet=(800, 3000)),
    dict(rep=(1800, 4000), bet=(2500, 8000)), dict(rep=(4000, 9000), bet=(6000, 20000))]
GARAGES = [(175, 6000), (1000, 25000)]   # = progression.garages (balance pass: garage 2 in about 5 h of play, was never inside 12 h)
ROC = dict(rep=6000, entry=50000)
# cars by class: (value new, how well it races 1..6)
TUNE = dict(               # the game's numbers since the balance pass (DESIGN3_jobs.md); --old: before it
    race_rep_base=35,       # progression.raceResult: rep for a win = base + bet/100 (x1.5 at night)
    job_rep=10,             # sl_jobs: rep per job done
    fine_base=250, fine_offence=150, fine_racing=500,    # progression.policeFine
    heat_decay_per_min=0.01,  # sl_police: heat cooling per real minute (on top of the daily x0.7)
    crush_pay=250, hot_base=400, hot_per_km=220, test_top=1200, test_slope=3000,
)
if '--old' in sys.argv:
    TUNE.update(race_rep_base=20, job_rep=6, fine_base=400, fine_offence=300, fine_racing=1000, heat_decay_per_min=0.0, crush_pay=150,
                hot_base=1000, hot_per_km=600, test_top=1500, test_slope=4000)
CARS = [(6000, 1), (15000, 2), (30000, 3), (60000, 4), (120000, 5), (250000, 6)]

def is_night(h): return h >= NIGHT[0] or h < NIGHT[1]

def race_rep(won, bet, night, opp_rep, my_rep, pink=False):          # progression.raceResult
    against = max(0.5, min(2, (opp_rep + 200) / (my_rep + 200)))
    if won:
        rep = (TUNE['race_rep_base'] + min(80, bet / 100) + (60 if pink else 0)) * against
        if night: rep *= 1.5
    else:
        rep = (-30 if pink else -5) / against
    return round(rep)

def police_fine(racing): return TUNE['fine_base'] + TUNE['fine_offence'] + (TUNE['fine_racing'] if racing else 0)

# jobs: (name, unlock rep, night only, pay(dist m, rng) -> $, minutes(dist, rng), rep on success, fail chance)
def job_part(d, r):
    fragile = r.random() < 0.35
    pay = max(120, d / 1000 * 140 * (1.5 if fragile else 1) * 1.25)
    return round(pay, -1), (0.06 if fragile else 0.02)
JOBS = [
    ('part run', 0, False, lambda r: job_part(r.uniform(600, 2500), r), lambda r, d=None: 2 + r.uniform(600, 2500) / CITY_SPEED / 60, 6),
    ('courier', 0, False, lambda r: (round(max(120, r.uniform(400, 2500) / 1000 * 140 * (1.5 if r.random() < 0.2 else 1)), -1), 0.03), lambda r, d=None: 2 + r.uniform(400, 2500) / CITY_SPEED / 60, 6),
    ('taxi', 0, False, lambda r: (max(60, round(40 + r.uniform(600, 2500) / 1000 * 90, -1)), 0.02), lambda r, d=None: 2.5 + r.uniform(600, 2500) / CITY_SPEED / 60, 6),
    ('food (night)', 0, True, lambda r: (120 + round(r.uniform(900, 3000) / 1000 * 60, -1), 0.03), lambda r, d=None: 3 + r.uniform(900, 3000) / CITY_SPEED / 60, 6),
    ('crushing run', 0, False, lambda r: (TUNE['crush_pay'], 0.05), lambda r, d=None: 2 + 1300 / 8 / 60, 6),
    ('car transport', 200, False, lambda r: (300 + round(r.uniform(1000, 2000) / 1000 * 120, -1), 0.15), lambda r, d=None: 2 + r.uniform(1000, 2000) / CITY_SPEED / 60, 6),
    ('recovery', 300, False, lambda r: (round(200 + r.uniform(500, 2500) / 1000 * 150, -1), 0.05), lambda r, d=None: 2.5 + r.uniform(500, 2500) / 8 / 60, 6),
    ('test driver', 600, False, lambda r: (round(TUNE['test_top'] - (r.uniform(1.15, 1.35) - 1.15) * TUNE['test_slope'], -2), 0.3), lambda r, d=None: 6.0, 6),
    ('hot car (night)', 1000, True, lambda r: (TUNE['hot_base'] + round(r.uniform(1000, 3000) / 1000 * TUNE['hot_per_km'], -2), 0.25), lambda r, d=None: 3 + r.uniform(1000, 3000) / CITY_SPEED / 60, 6),
    # suspected loop (review, B31): a quarter-mile "tune to spec" with the baseline run driven slowly on purpose, then a
    # $20 part and a real run: core/wwjobs pays the tier's purse plus the under-budget bonus for two strip runs
    # (B31 fixed: at least 35 % of the budget must go into the car, so the cash side of a tune to spec is never a profit)
    ('tune sandbag (B31)', 500, False, lambda r: (lambda t: (round(t[0] * 1.2, -1) - 0.35 * t[1], 0.1))(r.choice([(500, 2000), (900, 3500), (1500, 5500), (2200, 8500), (3000, 13000)][:1 + min(4, int(r.random() * 5))])), lambda r, d=None: 8 + r.uniform(0, 4), 6),
]

class Player:
    def __init__(self, seed, style):
        self.r = random.Random(seed)
        self.style = style                 # 'racer' | 'worker' | 'mixed'
        self.money, self.rep, self.heat = START_MONEY, 0, 0.0
        self.t = 0.0                        # real minutes
        self.car = None                     # class index into CARS, or None
        self.garage = 1
        self.log = {}                       # milestone -> minute
        self.earned = {}                    # source -> [money, minutes]
        self.fines, self.broke = 0, 0
        self.series = []
        self.flip_target = 1000
        self.kit = set()
        self.car_paid = 0
        self.perf = 0.0                     # parts on the car, in car classes
        self.upgraded = False               # the first part bought (ends "new in town")
        self.kind_done = {}
        self.crew = None                    # [tier, wins needed, pay]
        self.loan = None                    # core/bank: [borrowed, owed, nextDue day, missed]
        self.repossessed = 0
        if style == 'borrower':             # takes the full loan at once (core/bank.loanLimit at 0 rep, the first garage, a $3,000 starter car)
            self.loan = [4500, 4500, 7, 0]
            self.money += 4500

    def hour(self): return (20.5 + self.t / DAY_MIN * 24) % 24
    def day(self): return int((20.5 / 24 * DAY_MIN + self.t) // DAY_MIN)

    def mark(self, key):
        if key not in self.log: self.log[key] = self.t

    def book(self, src, money, minutes):
        e = self.earned.setdefault(src, [0, 0])
        e[0] += money; e[1] += minutes

    def spend(self, minutes):
        before = self.day()
        self.t += minutes
        if self.day() != before:
            self.heat *= 0.7                            # police: heat cools daily
            if self.loan:                               # core/bank: interest, the weekly quarter, two warnings
                self.loan[1] = min(self.loan[0] * 1.5, round(self.loan[1] * 1.03))
                if self.day() >= self.loan[2]:
                    self.loan[2] = self.day() + 7
                    due = min(self.loan[1], max(100, math.ceil(self.loan[1] / 4)))
                    if self.money >= due:
                        self.money -= due; self.loan[1] -= due; self.loan[3] = 0
                    else:
                        self.loan[3] += 1
                        if self.loan[3] >= 3: self.repossessed += 1; self.car = None; self.loan = None
                if self.loan and self.loan[1] <= 0: self.loan = None
            if self.loan and self.money > self.loan[1] * 3:   # pays it off once comfortable
                self.money -= self.loan[1]; self.loan = None
        self.heat = max(0.0, self.heat - TUNE['heat_decay_per_min'] * minutes)
        if not self.series or self.t - self.series[-1][0] >= 5: self.series.append((self.t, self.money, self.rep))
        if self.t > 20 and self.money < 300: self.broke_min = getattr(self, 'broke_min', 0) + minutes   # the floor check

    def tier(self):
        t = 0
        for i, d in enumerate(TIERS):
            if self.rep >= d['rep'][0]: t = i
        return t

    # ---- the choices
    def buy_car(self):
        # the best used car the money buys, keeping $800 for fuel and fixes; tired stock at half value
        best = None
        for i, (value, _) in enumerate(CARS):
            price = value * self.r.uniform(0.3, 0.6)          # damaged stock (0.3) to tired (0.5-0.6), market.lua
            trade = min(CARS[self.car][0] * 0.4, 0.9 * self.car_paid) if self.car is not None else 0   # (the sell-back cap)
            if price <= self.money + trade - 800 and (best is None or i > best[0]): best = (i, price, trade)
        if best and (self.car is None or best[0] > self.car):
            i, price, trade = best
            if self.car is not None:
                profit = trade - CARS[self.car][0] * 0.5
                if profit > self.flip_target: self.money += self.flip_target * 0.5; self.flip_target *= 1.6
            self.money += trade - price
            self.car, self.car_paid = i, price
            self.spend(8)
            self.mark('car %d' % (i + 1))
            return True
        return False

    def race(self):
        t = self.tier()
        opp_tier = max(0, min(4, min(t, CARS[self.car][1] - 1) + self.r.choice([-1, 0, 0, 0, 1])))
        bet = round(self.r.uniform(*TIERS[opp_tier]['bet']) / 50) * 50
        if bet > self.money * 0.5: return False
        opp_rep = self.r.uniform(*TIERS[opp_tier]['rep'])
        p_win = 1 / (1 + math.exp(-((CARS[self.car][1] - 1 + self.perf - opp_tier) * 1.1 + 0.3)))
        won = self.r.random() < p_win
        night = is_night(self.hour())
        minutes = 7 + self.r.uniform(0, 3)
        self.money += bet if won else -bet
        self.rep += race_rep(won, bet, night, opp_rep, self.rep)
        self.book('street race', bet if won else -bet, minutes)
        if won and self.crew and opp_tier + 1 >= self.crew[0]:
            self.crew[1] -= 1
            if self.crew[1] <= 0:
                self.money += self.crew[2]; self.book('crew contract', self.crew[2], 0); self.crew = None
        # police: heat from the race, maybe a pursuit, maybe caught
        self.heat = min(1, self.heat + 0.12)
        if self.r.random() < (0.15 + 0.55 * self.heat) * (1 if night else 0.3):
            if self.r.random() < 0.4:
                fine = police_fine(True)
                paid = min(self.money, fine)
                self.money -= paid; self.fines += paid; self.rep -= 25; self.heat = min(1, self.heat + 0.2)
                if paid < fine: self.broke += 1
            else:
                self.rep += 15
        self.spend(minutes)
        return True

    def job(self):
        night = is_night(self.hour())
        options = [j for j in JOBS if self.rep >= j[1] and (not j[2] or night)]
        if not options: return False
        name, _, night_only, pay_fn, min_fn, _ = self.r.choice(options)
        rep = TUNE['job_rep']
        pay, fail = pay_fn(self.r)
        minutes = min_fn(self.r)
        if self.r.random() < fail: pay = 0
        if not night_only: pay = round(pay * DAY_PAY, -1)     # sl_jobs.refresh: every day job's pay x jobsLib.DAY_PAY
        if pay and BOOST:                   # sl_jobs: "new in town" and the first-time bonus
            n = self.kind_done[name] = self.kind_done.get(name, 0) + 1
            mult = 1 if self.upgraded else 1 + max(0, 1 - self.rep / 150)
            pay = round(pay * mult, -1) + (150 if n <= 2 else 0)
        self.money += pay; self.rep += rep if pay else -5
        self.book(name, pay, minutes)
        self.spend(minutes)
        return True

    def sprint(self):
        if not is_night(self.hour()): return False
        stars = self.r.choice([0, 1, 1, 2, 2, 3])
        passed = self.r.random() < 0.7
        net = -100 + (round(400 * (1 + 0.25 * stars), -1) if passed else 0)
        self.money += net; self.rep += 15 if passed else 0
        self.book('street sprint', net, 5)
        self.spend(5)
        return True

    def part(self):
        price = self.r.uniform(600, 1500)
        if self.money < price + 800: return False
        self.money -= price; self.perf += price / 6000; self.upgraded = True
        self.mark('first upgrade')
        self.spend(4)
        return True

    def flip(self):
        # the SLRR flip as core/market prices it now: a damaged-stock car bought, repaired in your garage up to
        # condition 0.9, sold to a private buyer: min(what it is worth fixed, 0.9 x paid + 1.35 x the repairs)
        affordable = [v for v, _ in CARS if v * 0.35 + v * 0.25 < self.money - 500]
        if not affordable: return False
        v = max(affordable)                          # the best wreck you can afford
        c = self.r.uniform(0.2, 0.5)
        price = v * 0.3 * (0.85 + 0.3 * c) * self.r.uniform(0.92, 1.08)
        repairs = max(0.0, (0.9 - c) * v / 3)
        sale = min(v * (0.25 + 0.45 * 0.9), 0.9 * price + 1.35 * repairs)
        if self.r.random() < 0.5: sale *= 1.15        # rebuilt with no fault left in it (about half the wrecks): the premium
        else:
            # suspected loop (review, B25): a fault is cleared the moment a part whose slot path names it is *bought*, and
            # the part sells back at sellFactor, so every fault is worth 5 % of the car's value for a cheap part
            # (B25 fixed: a fault is fixed only with the part on the car at drive-out, worth at most 1.35 x its price)
            faults = self.r.randint(1, 3)
            wash = (min(v * 0.05, 1.35 * 60) - 60) * faults
            self.book('fault wash (B25)', wash, 2 * faults); sale += wash
        profit = sale - price - repairs
        minutes = self.r.uniform(25, 45)
        bonus = 0
        if profit >= self.flip_target: bonus = round(self.flip_target * 0.5, -1); self.flip_target *= 1.6
        self.money += profit + bonus
        self.book('lot flip', profit + bonus, minutes)
        self.spend(minutes)
        return True

    def step(self):
        self.rep = max(0, self.rep)                  # state.addRep: never below nothing
        if self.rep >= 300 and self.crew is None and not getattr(self, 'crew_done', False):
            self.crew = [max(1, min(5, 1 + int(self.rep / 800))), 3, round(2000 * max(1, min(5, 1 + int(self.rep / 800))) ** 1.3, -2)]
            self.crew_done = True
        # a player with the reputation for the next garage saves for it: no new parts, car or kit until it is bought
        # (the first week's curve is read off these players; an owner of a garage 2 who never saved would never see it)
        saving = self.garage < len(GARAGES) + 1 and self.car is not None and self.rep >= GARAGES[self.garage - 1][0]
        if not saving and self.car is not None and self.perf < 1.5 and self.r.random() < 0.15 and self.part(): return
        nxt = min(5, (self.car or 0) + 1)
        trade = CARS[self.car][0] * 0.4 if self.car is not None else 0
        if self.car is None or (not saving and self.money + trade > CARS[nxt][0] * 0.5 + 800 and self.r.random() < 0.5):
            if self.buy_car(): return
            if self.car is None:
                self.job() if self.rep >= 0 and any(not j[2] for j in JOBS) else self.spend(5)
                return
        # garage moves when both are there
        for lvl, (rep, cost) in enumerate(GARAGES, start=2):
            if self.garage == lvl - 1 and self.rep >= rep and self.money >= cost + 2000:
                self.money -= cost; self.garage = lvl; self.mark('garage %d' % lvl); return
        if self.garage == 3 and self.rep >= ROC['rep'] and self.money >= ROC['entry'] + 5000: self.mark('ROC open')
        # garage kit (X58, core/progression UPGRADES): bought once the first bolt-ons are on, with a cushion left over;
        # the club garages (2, 3) come with the lift and the bench
        if 'first upgrade' in self.log and not saving:
            for name, price in (('lift', 2000), ('workbench', 1500), ('shelves', 1000), ('dyno', 6000), ('paint', 5000)):
                if name in self.kit or (self.garage >= 2 and name in ('lift', 'workbench')): continue
                if self.money >= price + 1500:
                    self.money -= price; self.kit.add(name); self.mark(name); self.spend(2); return
                break
        w = {'racer': 0.75, 'mixed': 0.5, 'worker': 0.25, 'borrower': 0.5}[self.style]
        roll = self.r.random()
        if roll < w and self.race(): return
        if roll < w + 0.1 and self.sprint(): return
        if self.style != 'racer' and roll > 0.92 and self.flip(): return
        if not self.job(): self.spend(5)             # nothing on: time passes

    def run(self, minutes):
        while self.t < minutes:
            self.step()
            for m in (150, 300, 500, 800, 1000, 1500, 3000, 6000):
                if self.rep >= m: self.mark('rep %d' % m)
            if self.money <= 0: self.broke += 0          # (counted at arrests)
        return self

def main():
    players = []
    for i in range(PLAYERS + PLAYERS // 3):
        style = ['racer', 'mixed', 'worker', 'borrower'][i % 4]
        players.append(Player(i, style).run(60 * HOURS))
    keys = ['car 1', 'first upgrade', 'lift', 'workbench', 'dyno', 'car 2', 'car 3', 'car 4', 'rep 150', 'rep 300', 'rep 500', 'rep 800', 'rep 1000', 'rep 1500', 'garage 2', 'rep 3000', 'garage 3', 'rep 6000', 'ROC open']
    print('Milestones (real minutes of play; median and 10-90 %; n = players who got there in HOURS h)')
    for style in ['racer', 'mixed', 'worker', 'borrower']:
        print('  ' + style)
        ps = [p for p in players if p.style == style]
        for k in keys:
            ts = sorted(p.log[k] for p in ps if k in p.log)
            if ts:
                print('    %-10s %6.0f  (%4.0f-%4.0f)  n=%d' % (k, statistics.median(ts), ts[len(ts) // 10], ts[len(ts) * 9 // 10], len(ts)))
            else:
                print('    %-10s   never' % k)
    print('\nPay per real minute (all players)')
    totals = {}
    for p in players:
        for src, (m, mins) in p.earned.items():
            t = totals.setdefault(src, [0, 0]); t[0] += m; t[1] += mins
    for src, (m, mins) in sorted(((k, v) for k, v in totals.items() if v[1] > 0), key=lambda kv: -kv[1][0] / max(1, kv[1][1])):   # (contracts take no time of their own)
        print('  %-16s $%6.0f / min   (%d min sampled)' % (src, m / max(1, mins), mins))
    for style in ['racer', 'mixed', 'worker', 'borrower']:
        ps = [p for p in players if p.style == style]
        worth = sorted(p.money - (p.loan[1] if p.loan else 0) for p in ps)
        print('Net worth at the end (%s): median $%d; repossessions %d; loans still open %d'
              % (style, statistics.median(worth), sum(p.repossessed for p in ps), sum(1 for p in ps if p.loan)))
        bm = sorted(getattr(p, 'broke_min', 0) for p in ps)
        print('Floor (%s): minutes under $300 after the first 20: median %d, worst %d; players who ended under $300: %d of %d'
              % (style, statistics.median(bm), bm[-1], sum(1 for p in ps if p.money < 300), len(ps)))
    fines = [p.fines for p in players]
    print('\nPolice: median fines over the run $%d; players who could not pay a fine at least once: %d of %d' % (statistics.median(fines), sum(1 for p in players if p.broke), len(players)))
    if '--plot' in sys.argv:
        import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
        fig, ax = plt.subplots(2, 1, figsize=(9, 7), sharex=True)
        for p in players[:12]:
            ts = [s[0] / 60 for s in p.series]
            ax[0].plot(ts, [s[1] for s in p.series], lw=0.8); ax[1].plot(ts, [s[2] for s in p.series], lw=0.8)
        ax[0].set_ylabel('money $'); ax[1].set_ylabel('reputation'); ax[1].set_xlabel('hours of play')
        fig.savefig(sys.argv[sys.argv.index('--plot') + 1], dpi=110)

if __name__ == '__main__':
    main()
