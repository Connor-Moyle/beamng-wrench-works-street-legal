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

PLAYERS, HOURS = int(os.environ.get('PLAYERS', '45')), int(os.environ.get('HOURS', '12'))   # simulated players, hours of play each
DAY_PAY = float(os.environ.get('DAY_PAY', '1.35'))     # = core/jobs.lua DAY_PAY
CARS_KEPT = int(sys.argv[sys.argv.index('--cars') + 1]) if '--cars' in sys.argv else 1      # cars stored for the weekly storage bill (the sim plays one)
WEAR_SCALE = float(os.environ.get("WEAR_SCALE", "40"))   # core/service.lua SCALE
WEAR = '--nowear' not in sys.argv          # core/service.lua: wear x40 paid back as repairs, and a basic service every 150 km
SPONSOR = '--nosponsor' not in sys.argv       # core/brands.lua: standing from wins, a sponsorship at 100 with a retainer and a parts discount
SHOW = '--noshow' not in sys.argv      # core/show.lua: the Saturday Style show (a purse by place, entered when the car is in show shape)
WEEKLY = '--noweekly' not in sys.argv
SEASON = '--noseason' not in sys.argv      # sl_calendar weekend races and sl_season: the championship season (six rounds, a prize every three weeks)      # the weekly costs of core/weekly.lua
BOOST = '--noboost' not in sys.argv     # the early-game boost in sl_jobs
BEATS = '--nobeats' not in sys.argv     # sl_rivalbeats: the hunt's sweetener and the crew nights
SHOPS = '--noshops' not in sys.argv     # what the shops of sl_shops take (docs/SHOPS_REWORK.md step 3): (price, how often a week) of the services a player buys now and then; a guess to check in game
SHOP_WEEK = [('wash', 15, 3.0), ('scratch polish', 120, 0.6), ('dyno run', 90, 0.4), ('respray', 450, 0.08), ('special order (performance)', 1500, 0.12)]
NEEDS = '--needs' in sys.argv           # the Needs part (off by default in the game): food and drink every day: two drinks (2), a snack (3) and a meal (12) = $19 a day; --plan: the meal plan ($60 a week) pays the meals
NEEDS_PLAN = '--plan' in sys.argv
NEEDS_WEEK = (60 + 7 * 7) if NEEDS_PLAN else 7 * 19      # the plan: $60 + drinks and a snack every day ($7); without: $19 a day
SHOP_SPONSOR = float(os.environ.get('SHOP_FACTOR', '1.0'))      # a sponsor's price factor (sl_shops.setPriceFactor), 0.9 = ten per cent off
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
SHOW_W = dict(paint=0.25, wheels=0.15, parts=0.20, clean=0.15, body=0.15, wear=0.10)       # core/show.lua WEIGHTS
SHOW_MEAN, SHOW_PURSE, SHOW_FEE = [0.40, 0.50, 0.60, 0.70, 0.80], [300, 500, 800, 1100, 1500], 60
TUNE = dict(               # the game's numbers since the balance pass (DESIGN3_jobs.md); --old: before it
    race_rep_base=35,       # progression.raceResult: rep for a win = base + bet/100 (x1.5 at night)
    job_rep=10,             # sl_jobs: rep per job done
    fine_base=250, fine_offence=150, fine_racing=500,    # progression.policeFine
    ticket_base=120, ticket_offence=60, pullover=0.35,    # core/chase: a pull-over at level 1 is a ticket (police batch 2); the share of caught chases that are pull-overs at night
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
def ticket_fine(): return TUNE['ticket_base'] + TUNE['ticket_offence']

# jobs: (name, unlock rep, night only, pay(dist m, rng) -> $, minutes(dist, rng), rep on success, fail chance)
def job_part(d, r):
    fragile = r.random() < 0.35
    pay = max(120, d / 1000 * 140 * (1.5 if fragile else 1) * 1.25)
    return round(pay, -1), (0.06 if fragile else 0.02)
JOBS = [
    ('part run', 0, False, lambda r: job_part(r.uniform(600, 2500), r), lambda r, d=None: 2 + r.uniform(600, 2500) / CITY_SPEED / 60, 6),
    ('courier', 0, False, lambda r: (round(max(120, r.uniform(400, 2500) / 1000 * 140 * (1.5 if r.random() < 0.2 else 1)), -1), 0.03), lambda r, d=None: 2 + r.uniform(400, 2500) / CITY_SPEED / 60, 6),
    ('taxi', 0, False, lambda r: (max(60, round((40 + r.uniform(600, 2500) / 1000 * 90) * 1.25, -1)), 0.02), lambda r, d=None: 2.5 + r.uniform(600, 2500) / CITY_SPEED / 60, 6),
    ('food (night)', 0, True, lambda r: (120 + round(r.uniform(900, 3000) / 1000 * 60, -1), 0.03), lambda r, d=None: 3 + r.uniform(900, 3000) / CITY_SPEED / 60, 6),
    ('crushing run', 0, False, lambda r: (TUNE['crush_pay'], 0.05), lambda r, d=None: 2 + 1300 / 8 / 60, 6),
    ('car transport', 200, False, lambda r: (300 + round(r.uniform(1000, 2000) / 1000 * 120, -1), 0.15), lambda r, d=None: 2 + r.uniform(1000, 2000) / CITY_SPEED / 60, 6),
    ('recovery', 300, False, lambda r: (round(200 + r.uniform(500, 2500) / 1000 * 150, -1), 0.05), lambda r, d=None: 2.5 + r.uniform(500, 2500) / 8 / 60, 6),
    ('test driver', 600, False, lambda r: (round(TUNE['test_top'] - (r.uniform(1.15, 1.35) - 1.15) * TUNE['test_slope'], -2), 0.3), lambda r, d=None: 6.0, 6),
    # day job variety (sl_jobs scrapparts / tow / dealerdrive; the taxi's pay carries an average comfort tip of a quarter of the fare)
    ('scrapyard parts', 0, False, lambda r: (lambda d: (round(max(120, d / 1000 * 140 * 1.5), -1), 0.06))(r.uniform(1200, 3000)), lambda r, d=None: 2 + r.uniform(1200, 3000) / CITY_SPEED / 60, 6),
    ('patrol shift', 300, False, lambda r: (round(180 + sum(max(80, 220 - 2 * max(0, r.uniform(15, 120) - 20)) for _ in range(r.choice([1, 2, 2, 3]))) - r.choice([0, 0, 40, 120]), -1), 0.12), lambda r, d=None: 13 + r.uniform(0, 3), 6),      # sl_patrol: a ten-minute shift, one to three arrests paid by speed, a damage charge now and then
    ('tow job', 300, False, lambda r: (lambda d: (round(240 + d / 1000 * 180, -1), 0.1))(r.uniform(600, 2500)), lambda r, d=None: 3 + r.uniform(600, 2500) / 6 / 60, 6),
    ('dealer delivery', 200, False, lambda r: (lambda d: (320 + round(d / 1000 * 120, -1), 0.15))(r.uniform(800, 3000)), lambda r, d=None: 2 + r.uniform(800, 3000) / CITY_SPEED / 60, 6),
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
        self.weekend_done, self.season_points, self.season_rounds = -1, 0, 0
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
        self.standing, self.sponsor = 0.0, None          # brand standing (the sim plays one brand), the sponsorship {since, strikes, wins}
        self.weekWins, self.sponsorPaid = 0, 0
        self.inv = {'given': 0, 'last': -99, 'day': None, 'money': 0, 'standing': 0, 'trophies': 0}          # core/invite: brand invitationals
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
        if WEAR and self.car is not None:           # 70 % of the time is driving, at 40 km/h; wear per minute = 0.5 x 26.7 km-eq x sum(1/LIFE of 5 sections) = 4.6e-4 of the value / REPAIR_CONDITION 3
            km = minutes * 0.7 * 40 / 60
            value = CARS[self.car][0]
            self.money -= min(self.money, WEAR_SCALE / 40 * 4.6e-4 * value / 3 * minutes * 0.7 + (30 + 0.002 * value) * km / 150)
        if self.day() != before:
            self.heat *= 0.7                            # police: heat cools daily
            if SPONSOR:                                 # core/brands + sl_sponsor: decay 1 a day; an offer at 100 (taken); every 7th day since: the wins of the week
                self.standing = max(0.0, self.standing - 1)
                if not self.sponsor and self.standing >= 100:
                    self.sponsor = {'since': self.day(), 'strikes': 0}
                elif self.sponsor and (self.day() - self.sponsor['since']) % 7 == 0 and self.day() != self.sponsor['since']:
                    need = 3 if self.standing >= 300 else 2
                    if self.weekWins >= need:
                        pay = min(1500, round(150 + self.standing * 0.5, -1))
                        self.money += pay; self.sponsorPaid += pay; self.sponsor['strikes'] = 0
                    else:
                        self.sponsor['strikes'] += 1
                        if self.sponsor['strikes'] >= 3: self.sponsor, self.standing = None, max(0.0, self.standing - 30)
                    self.weekWins = 0
                self.invitational()
            if WEEKLY and self.day() % 7 == 0:          # core/weekly: garage rent (storage of cars beyond two is not simulated: the sim holds one car)
                bill = {1: 0, 2: int(os.environ.get("RENT2", "150")), 3: int(os.environ.get("RENT3", "400"))}.get(self.garage, 700)
                bill += 40 * max(0, CARS_KEPT - 2)       # core/weekly STORAGE for each car beyond two
                self.money -= min(self.money, bill)     # (a shortfall is a debt in the game; here it is just not paid, the floor check shows who runs dry)
            if NEEDS and self.day() % 7 == 0:               # the Needs part: the food and drink of the week (buying is by choice: nothing is bought with the last dollars)
                cost = min(self.money, NEEDS_WEEK)
                self.money -= cost; self.needs_spent = getattr(self, 'needs_spent', 0) + cost
            if SHOPS and self.day() % 7 == 0 and self.car is not None:      # the shops: a player buys what they can well afford (three times the price in the pocket), never the last dollars
                for name, price, per_week in SHOP_WEEK:
                    price = price * SHOP_SPONSOR
                    count = int(per_week) + (1 if self.r.random() < per_week - int(per_week) else 0)
                    for _ in range(count):
                        if self.money >= 3 * price:
                            self.money -= price; self.shop_spent = getattr(self, 'shop_spent', 0) + price
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

    def show(self):
        # core/show.lua: Saturday night, entry $60; six criteria with the weights of show.WEIGHTS; the field is seeded around the tier mean (show.TIER_MEAN); a 1st/2nd/3rd place
        # pays the purse, half, a quarter and reputation 12 + 8 x tier (half, quarter). The simulated player enters when the car is in show shape: a car bought, 2+ bolt-ons.
        if self.car is None or self.money < SHOW_FEE + 300 or self.perf < 0.5: return False
        tier = self.tier()
        w = SHOW_W
        paint = 0.45 + (0.30 if 'paint' in self.kit else 0.0)
        mine = dict(paint=paint, wheels=0.45 + (0.40 if self.perf > 0.8 else 0.0) + 0.1, parts=min(1.0, 0.55 * self.perf / 1.5 + 0.35 * min(1.0, self.perf / 1.5)),
                    clean=0.62 + (0.30 if self.r.random() < 0.5 else 0.0), body=0.85, wear=0.85)
        total = sum(w[k] * min(1.0, max(0.0, mine[k] + self.r.uniform(-0.07, 0.07))) for k in w)
        n = min(11, 7 + tier - 1)
        better = 0
        for _ in range(n):
            skill = min(0.97, max(0.05, SHOW_MEAN[tier - 1] + self.r.uniform(-0.18, 0.18)))
            rival = sum(w[k] * min(1.0, max(0.0, skill + self.r.uniform(-0.22, 0.22))) for k in w)
            if rival >= total: better += 1
        place = better + 1
        purse = SHOW_PURSE[tier - 1]
        share = {1: 1.0, 2: 0.5, 3: 0.25}.get(place, 0.0)
        prize = round(purse * share, -1)
        self.money += prize - SHOW_FEE
        self.rep += int((12 + 8 * tier) * share + 0.5)
        self.book('show', prize - SHOW_FEE, 14)          # the drive to the spot, the parking and the judging
        self.shows = getattr(self, 'shows', 0) + 1
        self.spend(14)
        return True

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

    def invitational(self):                          # core/invite: a sponsor of 4 weeks invites (3 at most, 14 days apart), the race is 5 days on; places 1/2/3 at 40/25/15 % in a race car lent by the brand
        v, d = self.inv, self.day()
        if v['day'] == d:
            place = self.r.choices([1, 2, 3, 4], [0.40, 0.25, 0.15, 0.20])[0]
            money, standing = {1: (3000, 100), 2: (1800, 60), 3: (1000, 30), 4: (300, 10)}[place]
            self.money += money; v['money'] += money; v['standing'] += standing; v['trophies'] += place == 1
            self.standing += standing
            self.book('invitational', money, 25)
            v['day'] = None
        elif v['day'] is None and v['given'] < 3 and self.sponsor and d - self.sponsor['since'] >= 28 and d - v['last'] >= 14:
            v['given'] += 1; v['last'] = d; v['day'] = d + 5

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
        if won and SPONSOR: self.standing += 10; self.weekWins += 1
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
                fine = ticket_fine() if (night and self.r.random() < TUNE['pullover']) else police_fine(True)
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

    def weekend_race(self):
        # sl_calendar + sl_gridrace: a weekend dockyards race (days 6 and 7 of the week, once a day, a fee and a purse by place); sl_season: six rounds, the prize every three weeks
        if not SEASON or self.car is None or self.day() % 7 not in (5, 6) or self.weekend_done == self.day(): return False
        self.weekend_done = self.day()
        fee, purse = (100, 500) if self.r.random() < 0.4 else (150, 800)
        p = 1 / (1 + math.exp(-((CARS[self.car][1] - 1 + self.perf) * 0.9 - 1.5)))
        roll = self.r.random()
        place = 1 if roll < p * 0.45 else (2 if roll < p * 0.8 else (3 if roll < p else self.r.randint(4, 7)))
        share = {1: 1.0, 2: 0.5, 3: 0.25}.get(place, 0)
        net = -fee + round(purse * share, -1)
        self.money += net; self.rep += {1: 40, 2: 20, 3: 10}.get(place, 5)
        self.book('weekend race', net, 9)
        self.season_points += [10, 7, 5, 3, 2, 1, 0][min(6, place - 1)]
        self.season_rounds += 1
        if self.season_rounds >= 6:
            # the table: six rivals who score like the player on average; the prize by position
            rivals = sorted(self.r.gauss(self.season_points, 9) for _ in range(6))
            pos = 1 + sum(1 for x in rivals if x > self.season_points)
            prize = round(2000 * {1: 1.0, 2: 0.55, 3: 0.3, 4: 0.15}.get(pos, 0), -1)
            self.money += prize; self.rep += {1: 30, 2: 20, 3: 10, 4: 5}.get(pos, 0)
            self.book('season prize', prize, 0)
            self.season_points, self.season_rounds = 0, 0
    def beats(self):
        """sl_rivalbeats: a pink-slip car won leads to a hunt (the rival's offer for the car; a sweetener of 25 % of its value on the second text, doubled on the third) and a beaten crew's three nights at 1.5 x the bet"""
        if not BEATS or not is_night(self.hour()) or self.car is None: return False
        r = self.r
        if r.random() < 0.5:                       # the hunt race: the car on the line (its value), the sweetener on a win at stage 2/3
            value = CARS[self.car][0]
            stage = r.choice([1, 2, 2, 3])
            sweet = round(value * 0.25 * (2 if stage == 3 else 1), -2) if stage >= 2 else 0
            if r.random() < 0.5: self.money += sweet; self.rep += 15; self.book('rival hunt (night)', sweet, 8)
            else: self.rep -= 5; self.book('rival hunt (night)', 0, 8)          # (the car goes back: the sim keeps one car, so only the rep moves)
        else:                                      # a night of the three
            bet = round(r.uniform(100, 300) * 1.5, -2)
            if r.random() < 0.55: self.money += bet; self.rep += 10; self.book('crew nights (night)', bet, 6)
            else: self.money -= bet; self.book('crew nights (night)', -bet, 6)
        self.spend(8)
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
        if SPONSOR and self.sponsor: price *= (0.85 if self.standing >= 300 else 0.90)          # the brand's parts: the sim buys all its parts from the sponsor
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
        if SHOW and (self.day() + 1) % 7 == 6 and getattr(self, 'show_day', -1) != self.day() and self.r.random() < 0.7:
            self.show_day = self.day()
            if self.show(): return
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
        if self.weekend_race(): return
        if roll < w and self.race(): return
        if roll < w + 0.1 and self.sprint(): return
        if self.style != 'worker' and self.rep >= 800 and roll > 0.9 and self.beats(): return
        if self.style != 'racer' and roll > 0.92 and self.flip(): return
        if not self.job(): self.spend(5)             # nothing on: time passes

    def run(self, minutes):
        while self.t < minutes:
            self.step()
            for m in (150, 300, 500, 800, 1000, 1500, 3000, 6000):
                if self.rep >= m: self.mark('rep %d' % m)
            if self.money <= 0: self.broke += 0          # (counted at arrests)
        return self

SEED = int(os.environ.get('SEED', '0'))          # which set of players: the players' streams are seeded 1000 x SEED + their number

def population(seed):
    players = []
    for i in range(PLAYERS + PLAYERS // 3):
        style = ['racer', 'mixed', 'worker', 'borrower'][i % 4]
        players.append(Player(i + 1000 * seed, style).run(60 * HOURS))
    return players

def metrics(players):
    out = {}
    for style in ['racer', 'mixed', 'worker', 'borrower']:
        ps = [p for p in players if p.style == style]
        worth = [p.money - (p.loan[1] if p.loan else 0) for p in ps]
        out[style + ' net worth (median)'] = statistics.median(worth)
        out[style + ' floor minutes (median)'] = statistics.median([getattr(p, 'broke_min', 0) for p in ps])
        out[style + ' floor minutes (worst)'] = max(getattr(p, 'broke_min', 0) for p in ps)
        out[style + ' under $300 at the end'] = sum(1 for p in ps if p.money < 300)
    return out

def spread(values):
    v = sorted(values)
    return statistics.median(v), v[0], v[-1]

def multi(n):
    """--seeds N [--json file]: N independent populations; each number as median and range over the seeds. Same code, same numbers; a change of the rules moves the median by more than the range or it says nothing."""
    runs = [metrics(population(k)) for k in range(n)]
    table = {key: spread([r[key] for r in runs]) for key in runs[0]}
    if '--json' in sys.argv:
        import json
        json.dump(table, open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=1)
    print('%d seeds of %d players, %d h each: median (lowest - highest over the seeds)' % (n, PLAYERS + PLAYERS // 3, HOURS))
    for key, (m, lo, hi) in table.items(): print('  %-34s %9.0f  (%.0f - %.0f)' % (key, m, lo, hi))

def diff(a, b):
    """--diff before.json after.json: each number's change in the median, and whether the two ranges overlap (overlap: no real change)."""
    import json
    A, B = json.load(open(a)), json.load(open(b))
    print('%-34s %10s %10s %9s' % ('', 'before', 'after', 'change'))
    for key in A:
        if key not in B: continue
        (ma, la, ha), (mb, lb, hb) = A[key], B[key]
        real = hb < la or lb > ha
        print('%-34s %10.0f %10.0f %+9.0f %s' % (key, ma, mb, mb - ma, 'REAL' if real else '(within the spread)'))

def turf_check(n):
    """--turf [--seeds N]: the late game with turf income (docs/TURF_INCOME_PLAN.md). Not the 12 h sim (garage 3 is outside it): a year of weeks for a player who holds 2 to 6 districts at
    60 to 100 % control, with the rules of core/turfincome.lua mirrored here (cut = 100 x control, +50 % at the base, a raid chance 12 % + 8 % per angry crew costing the cut and 15 control,
    10 control won back a week by racing there, an unanswered call-out 15 % of district-weeks). Prints the weekly turf money against the garage-3 rent and storage and against the weekly pay
    of the populations the sim plays (the sim's own median over the same seeds). Acceptance: 40 to 100 % of garage-3 costs at 4 to 6 districts, and far below the weekly pay."""
    import random
    garage3 = 400 + 40 * max(0, CARS_KEPT - 2)
    rows, pay = [], []
    for seed in range(n):
        rng = random.Random(seed)
        pops = population(seed)
        weeks = HOURS * 60 / DAY_MIN / 7
        pay.append(statistics.median(sum(m for m, _ in p.earned.values()) / weeks for p in pops))
        for k in (2, 3, 4, 5, 6):
            money, lost, raids = 0.0, 0.0, 0
            control = [rng.uniform(60, 100) for _ in range(k)]
            base = 0 if rng.random() < 0.5 else -1
            angry = rng.choice((0, 1, 2))
            for _week in range(52):
                for i in range(k):
                    cut = 100 * control[i] / 100 * (1.5 if i == base else 1.0)
                    cut = int(cut / 10 + 0.5) * 10
                    if rng.random() < min(0.5, 0.12 + 0.08 * angry):
                        raids += 1; lost += cut
                        control[i] = max(1, control[i] - 15 * (0.5 if i == base else 1))
                    elif rng.random() < 0.15:
                        lost += cut
                    else:
                        money += cut
                    control[i] = min(100, control[i] + 10)
            rows.append((k, money / 52, lost / 52, raids / 52))
    print('Turf income over a year of weeks (%d seeds): garage 3 rent+storage $%d a week; the sim median weekly pay $%d' % (n, garage3, statistics.median(pay)))
    for k in (2, 3, 4, 5, 6):
        got = [r for r in rows if r[0] == k]
        m = statistics.median(r[1] for r in got)
        print('  %d districts held: $%4d a week paid (%3.0f %% of garage 3, %4.1f %% of the weekly pay), $%3d a week lost to raids and call-outs, %.2f raids a week'
              % (k, m, 100 * m / garage3, 100 * m / max(1, statistics.median(pay)), statistics.median(r[2] for r in got), statistics.median(r[3] for r in got)))

def main():
    if '--turf' in sys.argv:
        turf_check(int(sys.argv[sys.argv.index('--seeds') + 1]) if '--seeds' in sys.argv else 3); return
    if '--diff' in sys.argv:
        i = sys.argv.index('--diff'); diff(sys.argv[i + 1], sys.argv[i + 2]); return
    if '--seeds' in sys.argv:
        multi(int(sys.argv[sys.argv.index('--seeds') + 1])); return
    players = population(SEED)
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
        spn = sorted(p.sponsorPaid for p in ps)
        print('Sponsor retainer paid (%s): median $%d, with a sponsor at the end: %d of %d' % (style, statistics.median(spn), sum(1 for p in ps if p.sponsor), len(ps)))
        iv = sorted(p.inv['money'] for p in ps)
        print('Invitationals (%s): median purse $%d (max $%d), given %d / raced %d, standing gained median %d, trophies %d' % (style, statistics.median(iv), iv[-1], sum(p.inv['given'] for p in ps), sum(1 for p in ps if p.inv['money'] > 0), statistics.median(sorted(p.inv['standing'] for p in ps)), sum(p.inv['trophies'] for p in ps)))
        bm = sorted(getattr(p, 'broke_min', 0) for p in ps)
        print('Floor (%s): minutes under $300 after the first 20: median %d, worst %d; players who ended under $300: %d of %d'
              % (style, statistics.median(bm), bm[-1], sum(1 for p in ps if p.money < 300), len(ps)))
    if NEEDS:
        eaten = sorted(getattr(p, 'needs_spent', 0) for p in players)
        print('Needs (%s): median spend over the run $%d (10-90 %%: $%d-$%d)' % ('meal plan' if NEEDS_PLAN else 'no plan', statistics.median(eaten), eaten[len(eaten) // 10], eaten[len(eaten) * 9 // 10]))
    if SHOPS:
        spent = sorted(getattr(p, 'shop_spent', 0) for p in players)
        earned = sorted(sum(m for m, _ in p.earned.values()) for p in players)
        print('Shops (SHOP_WEEK, factor %.2f): median spend over the run $%d (10-90 %%: $%d-$%d), %.1f %% of the median income $%d' % (SHOP_SPONSOR, statistics.median(spent), spent[len(spent) // 10], spent[len(spent) * 9 // 10], 100 * statistics.median(spent) / max(1, statistics.median(earned)), statistics.median(earned)))
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
