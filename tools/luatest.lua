-- Tests of the game rules (sl/core). Run with: node tools/luatest.js

local rngLib = require('sl/core/rng')
local progression = require('sl/core/progression')
local roster = require('sl/core/roster')
local market = require('sl/core/market')
local state = require('sl/core/state')

local passed = 0
local function check(name, ok, detail)
  if not ok then error('FAILED: ' .. name .. (detail and (' (' .. tostring(detail) .. ')') or ''), 2) end
  passed = passed + 1
end

-- rng: the same seed, the same numbers; ranges hold
do
  local a, b = rngLib.new(42), rngLib.new(42)
  local same = true
  for _ = 1, 50 do if a:next() ~= b:next() then same = false end end
  check('rng repeats for a seed', same)
  local r, lo, hi = rngLib.new(7), 99, -99
  for _ = 1, 5000 do
    local x = r:int(3, 9)
    lo, hi = math.min(lo, x), math.max(hi, x)
  end
  check('rng int stays in range and reaches both ends', lo == 3 and hi == 9, lo .. '..' .. hi)
  local f = rngLib.new(0):float()
  check('rng float in [0,1)', f >= 0 and f < 1)
  check('hash differs by text', rngLib.hash('used:1:2') ~= rngLib.hash('used:1:3'))
end

-- progression
do
  check('titles', progression.titleFor(0) == 'Nobody' and progression.titleFor(150) == 'Street kid' and progression.titleFor(99999) == 'King of Valo City')
  local _, nextRep = progression.titleFor(120)
  check('next title threshold', nextRep == 300, nextRep)
  local n = progression.nextGarage({ garageLevel = 1, rep = 100, money = 1e6 })
  check('garage 2 needs reputation', n and not n.canMove and n.why:find('reputation'))
  n = progression.nextGarage({ garageLevel = 1, rep = 2000, money = 100 })
  check('garage 2 needs money', n and not n.canMove and n.why:find('costs'))
  n = progression.nextGarage({ garageLevel = 1, rep = 2000, money = 30000 })
  check('garage 2 can be moved to', n and n.canMove and n.garage.level == 2)
  check('no garage above the last', progression.nextGarage({ garageLevel = 3 }) == nil)
  check('ROC closed below the top', not progression.rocOpen({ garageLevel = 2, rep = 9000 }))
  check('ROC open at the top', progression.rocOpen({ garageLevel = 3, rep = 6000 }))

  local dayRep, dayMoney = progression.raceResult({ won = true, stake = 'money', bet = 500, night = false, opponentRep = 300, playerRep = 300 })
  local nightRep = progression.raceResult({ won = true, stake = 'money', bet = 500, night = true, opponentRep = 300, playerRep = 300 })
  check('a win pays the bet', dayMoney == 500)
  check('night wins are worth more', nightRep > dayRep, dayRep .. ' / ' .. nightRep)
  local upRep = progression.raceResult({ won = true, bet = 500, opponentRep = 3000, playerRep = 100 })
  check('beating a big name is worth more', upRep > dayRep)
  local lossRep, lossMoney = progression.raceResult({ won = false, stake = 'money', bet = 500, opponentRep = 300, playerRep = 300 })
  check('a loss costs the bet and a little reputation', lossMoney == -500 and lossRep < 0)
  local _, pinkMoney = progression.raceResult({ won = true, stake = 'pink', bet = 0 })
  check('pink slips move no money', pinkMoney == 0)
  check('night hours', progression.isNight(23) and progression.isNight(2) and not progression.isNight(14))
  check('police fines grow with offences and racing', progression.policeFine(3, false) > progression.policeFine(1, false) and progression.policeFine(1, true) > progression.policeFine(1, false))
  check('caught costs reputation, escaping earns it', progression.ARREST_REP < 0 and progression.EVADE_REP > 0)
  check('fees grow with distance', progression.towFee(5000) > progression.towFee(500) and progression.taxiFee(0) > 0)
  local bare, club = progression.garageFeatures({}, 1), progression.garageFeatures({}, 2)
  check('garage 1 starts bare; the club garages come with the lift and bench', not bare.lift and not bare.dyno and bare.repairFactor > 1 and club.lift and club.workbench and club.repairFactor == 1)
  local bought = progression.garageFeatures({ dyno = true, shelves = true }, 1)
  check('what you buy is there', bought.dyno and bought.shelfSize > bare.shelfSize and not bought.paint)
  check('every upgrade has a price', (function() for _, u in ipairs(progression.UPGRADES) do if not (u.price > 0 and progression.upgrade(u.id) == u) then return false end end return true end)())
  check('back to the road is never free and grows with distance', progression.roadFee(0) > 0 and progression.roadFee(40) > progression.roadFee(5))
end

-- roster
do
  local a, b = roster.generate(1234, 36), roster.generate(1234, 36)
  check('roster size', #a == 36)
  check('roster repeats for a seed', a[10].name == b[10].name and a[30].phone == b[30].phone)
  local names, phones, tiers = {}, {}, { 0, 0, 0, 0, 0 }
  for _, r in ipairs(a) do
    check('racer has a sensible stake range ' .. r.id, r.betMin > 0 and r.betMax >= r.betMin)
    check('racer skill in range ' .. r.id, r.skill > 0 and r.skill < 1)
    names[r.name] = (names[r.name] or 0) + 1
    phones[r.phone] = (phones[r.phone] or 0) + 1
    tiers[r.tier] = tiers[r.tier] + 1
  end
  for n, c in pairs(names) do check('unique name ' .. n, c == 1) end
  for p, c in pairs(phones) do check('unique number ' .. p, c == 1) end
  check('more racers at the bottom than at the top', tiers[1] > tiers[5] and tiers[5] > 0, table.concat(tiers, ','))
  local other = roster.generate(99, 36)
  check('another seed, another crowd', other[1].name ~= a[1].name or other[2].name ~= a[2].name)

  local top, bottom = a[#a], a[1]
  local rng = rngLib.new(5)
  local r = roster.respond(top, 'race', { rep = 0, money = 1e6, hasCar = true }, rng)
  check('a top racer ignores a nobody', not r.accept and r.text ~= '')
  r = roster.respond(bottom, 'race', { rep = 0, money = 1e6, hasCar = false }, rng)
  check('nobody races you without a car', not r.accept)
  check('a stake goes up in tenths, at least $50', roster.stakeStep(1000) == 100 and roster.stakeStep(200) == 50)
  check('how far a stake goes depends on their car: 2x a beater, 4x a supercar',
    roster.maxStake({ class = 'beater' }, 1000) == 2000 and roster.maxStake({ class = 'super' }, 1000) == 4000 and roster.maxStake({ class = 'tuner' }, 1000) == 3500)
  r = roster.respond(bottom, 'race', { rep = 0, money = 1e6, hasCar = true }, rng)
  check('a bottom racer takes a money race', r.accept and r.stake == 'money' and r.bet >= bottom.betMin and r.bet <= bottom.betMax, r.bet)
  local high = roster.respond(bottom, 'high', { rep = 0, money = 1e6, hasCar = true }, rngLib.new(5))
  check('high stakes are three times the usual', high.accept and high.bet >= bottom.betMin * 3)
  r = roster.respond(bottom, 'race', { rep = 0, money = 10, hasCar = true }, rng)
  check('no race when you cannot cover the bet', not r.accept and r.text:len() > 0)
  local pinkOK, pinkNo
  for _, x in ipairs(a) do
    if x.tier == 1 and x.pinkOK then pinkOK = x end
    if x.tier == 1 and not x.pinkOK then pinkNo = x end
  end
  if pinkOK then
    r = roster.respond(pinkOK, 'pink', { rep = 0, money = 0, hasCar = true, pinkTonight = true }, rng)
    check('pink slips with somebody who races for cars, on their night', r.accept and r.stake == 'pink' and r.bet == 0)
    r = roster.respond(pinkOK, 'pink', { rep = 0, money = 0, hasCar = true, pinkTonight = false }, rng)
    check('but not on any other night', not r.accept and r.text ~= roster.respond(pinkNo or pinkOK, 'pink', { rep = 0, money = 0, hasCar = true, pinkTonight = true }, rng).text or not pinkNo)
  end
  -- pink nights are rare, change from night to night, and hold all night
  local nights, hits, changes, prev = 0, 0, 0, nil
  for _, x in ipairs(a) do
    for day = 1, 200 do
      local t = roster.pinkTonight(x, day, 77)
      check('the same answer all night', t == roster.pinkTonight(x, day, 77))
      if x.pinkOK then
        nights = nights + 1
        if t then hits = hits + 1 end
        if prev ~= nil and t ~= prev then changes = changes + 1 end
        prev = t
      else
        check('never for somebody who does not race for cars', not t)
      end
    end
    prev = nil
  end
  check('about one night in eight', nights > 0 and hits / nights > 0.07 and hits / nights < 0.18, hits .. '/' .. nights)
  check('a different night each time', changes > 0)
  if pinkNo then
    r = roster.respond(pinkNo, 'pink', { rep = 0, money = 0, hasCar = true }, rng)
    check('no pink slips with somebody who does not', not r.accept)
  end
  check('display name with a nickname', roster.displayName({ name = 'Mick Santana', nick = 'Clutch' }) == 'Mick "Clutch" Santana')
end

-- market
do
  local cars = {}
  for i = 1, 60 do
    cars[i] = { model = 'm' .. (i % 12), config = 'cfg' .. i, name = 'Car ' .. i, brand = 'B', value = 2000 + i * 2500 }
  end
  local used = market.offers(cars, 'used', 1, 3, 8)
  local again = market.offers(cars, 'used', 1, 3, 8)
  local tomorrow = market.offers(cars, 'used', 1, 4, 8)
  check('8 used cars', #used == 8)
  check('the same day, the same cars', used[1].config == again[1].config and used[8].price == again[8].price)
  local differ = false
  for i = 1, 8 do if used[i].config ~= tomorrow[i].config then differ = true end end
  check('another day, other cars', differ)
  local seen, cheapestFirst = {}, true
  for i, o in ipairs(used) do
    check('used offer has a price ' .. i, o.price >= 200 and o.price % 50 == 0, o.price)
    check('used offer is cheaper than new ' .. i, o.price < o.value * 1.3, o.price .. ' / ' .. o.value)
    check('condition and damage in range ' .. i, o.condition >= 0 and o.condition <= 1 and o.damage >= 0 and o.damage <= 1)
    check('no car twice ' .. i, not seen[o.config])
    seen[o.config] = true
    if i > 1 and used[i - 1].price > o.price then cheapestFirst = false end
  end
  check('cheapest first', cheapestFirst)
  local dealer = market.offers(cars, 'dealer', 1, 3, 6)
  for i, o in ipairs(dealer) do check('dealer cars are new and full price ' .. i, o.condition == 1 and o.damage == 0 and o.price >= o.value) end
  local scrap = market.offers(cars, 'scrap', 1, 3, 6)
  for i, o in ipairs(scrap) do check('scrap is cheap and bent ' .. i, o.price < o.value * 0.2 and o.damage >= 0.6, o.price) end
  check('nothing to sell from nothing', #market.offers({}, 'used', 1, 1, 5) == 0)
  -- a starter car: with the game's real values (nothing under $9,000 new) the used lot still has a car at the
  -- starter price every day, and it is the cheapest one on the lot
  do
    local dear = {}
    for i = 1, 60 do dear[i] = { model = 'm' .. (i % 12), config = 'd' .. i, name = 'Dear ' .. i, brand = 'B', value = 9000 + i * 3000 } end
    local ok = true
    for seed = 1, 40 do
      local o = market.offers(dear, 'used', seed, seed % 9 + 1, 6)
      if #o ~= 6 or o[1].price > market.STARTER_PRICE or o[1].condition > 0.75 then ok = false end
    end
    check('the used lot always has a starter at or under the starter price', ok)
    check('a starter is a real used car, not a loop', market.resaleValue({ value = 12000, condition = 0.5, faults = {}, boughtFor = 3500, partsAtBuy = 0 }, 0) < 3500)
  end
  -- B25: a fault is fixed only while a part sits in its slot at drive-out, and is worth at most 1.35 x that part
  do
    local car = { value = 20000, condition = 0.5, faults = { 'exhaust', 'engine' } }   -- (no sell-back cap: as a car won)
    local open = market.resaleValue(car, 0)
    car.fixed = { exhaust = 60 }
    local cheap = market.resaleValue(car, 0)
    check('a $60 part gives back at most $81 of the fault, not 5 % of the car', cheap - open <= 100 and cheap >= open)
    car.fixed = { exhaust = 2000, engine = 3000 }
    local proper = market.resaleValue(car, 0)
    check('proper parts get the whole fault back', proper > cheap and #market.unfixed(car) == 0)
    check('no fixed part, every fault open', #market.unfixed({ faults = { 'a', 'b' } }) == 2)
    local tree = { children = { engine = { path = '/engine/', chosenPartName = 'engine_v8', children = { exhaust = { path = '/engine/exhaust/', chosenPartName = '' } } } } }
    local f = market.faultsFitted(tree, { 'engine', 'exhaust', 'battery' })
    check('faultsFitted: a part in the slot counts, an empty slot does not', f.engine == true and not f.exhaust and not f.battery)
  end
  check('scrap pays less than a private buyer', market.scrapValue({ value = 20000, condition = 0.5 }) < market.resaleValue({ value = 20000, condition = 0.5 }))
  -- no money loop (fails the build): every car any lot sells, sold straight back or scrapped as it is, fetches
  -- less than it cost; fitting parts only gets their value back; a better state since is worth more
  local loops = {}
  for _, kind in ipairs({ 'used', 'dealer', 'scrap' }) do
    for seed = 1, 40 do
      for _, o in ipairs(market.offers(cars, kind, seed, seed % 9 + 1, 8)) do
        local car = { value = o.value, condition = o.condition, faults = o.faults, boughtFor = o.price, partsAtBuy = 5000 }
        local back, scrapped = market.resaleValue(car, 5000), market.scrapValue(car, 5000)
        if back >= o.price or scrapped >= o.price then loops[#loops + 1] = string.format('%s %s $%d -> $%d/$%d', kind, o.name, o.price, back, scrapped) end
        if market.resaleValue(car, 5000 + 800) > back + 800 then loops[#loops + 1] = 'parts pay more than they cost: ' .. o.name end
      end
    end
  end
  check('no car buys back for more than it cost (lot to lot, lot to scrap)', #loops == 0, loops[1])
  -- the flip: a wreck bought, repaired in your garage, sold: the repairs come back with a margin, as far as the car
  -- is worth fixed (and no further: repairing past that only loses money)
  local wreck = { value = 20000, condition = 0.3, faults = {}, boughtFor = 5000 }
  local function flip(spent) local c = { value = 20000, condition = 0.3, faults = {}, boughtFor = 5000, repaired = spent } return market.resaleValue(c) - 5000 - spent end
  check('a wreck sold straight back loses', flip(0) < 0)
  check('part fixed up it pays: 10-30 % on the repairs', flip(3000) > 3000 * 0.1 and flip(3000) < 3000 * 0.3, flip(3000))
  check('rebuilt all the way it pays best, 15-35 % of the whole outlay', flip(4100) > 9100 * 0.15 and flip(4100) < 9100 * 0.35, flip(4100))
  check('repairs past what it is worth fixed lose money', flip(30000) < 0)
  check('repairs raise what a pink slip car fetches too, but not past as good as new', market.resaleValue({ value = 20000, condition = 0.3, repaired = 1e6 }) <= market.resaleValue({ value = 20000, condition = 0.95 }) * market.REBUILT_PREMIUM)
  check('a wreck is a wreck: no faults fixed, no money', market.resaleValue(wreck) <= 5000 * 0.9)
  local function rebuilt(spent, faults) return market.resaleValue({ value = 20000, condition = 0.3, faults = faults or {}, boughtFor = 5000, repaired = spent }) end
  check('brought back to 0.9 yourself: the premium', rebuilt(4100) > rebuilt(3900) * 1.1)
  check('no premium with a fault still in it', rebuilt(4100, { 'radiator' }) < rebuilt(3900, { 'radiator' }) * 1.1)
  check('no premium for a car bought good (no loop)', not market.rebuilt({ value = 20000, condition = 0.95, faults = {}, boughtFor = 20000, repaired = 500 }))
  check('a new part puts its fault right', market.fixes('gearbox', '/main/transmission_6M') and market.fixes('tyres', '/wheel_FR/tire_FR') and not market.fixes('radiator', '/main/exhaust'))
  check('a pink slip won (nothing paid) sells at the going rate', market.resaleValue({ value = 20000, condition = 0.5 }) > 5000)
end

-- career save
do
  local s = state.new(77, 0)
  check('new career: start money, no rep, garage 1', s.money == progression.START_MONEY and s.rep == 0 and s.garageLevel == 1)
  check('new career has racers', #s.racers == 36)
  local added = state.refreshContacts(s)
  check('a nobody knows the bottom tier only', #added > 0 and added[1].tier == 1)
  for _, r in ipairs(added) do check('only tier 1 at the start ' .. r.id, r.tier == 1) end
  s.rep = 5000
  local more = state.refreshContacts(s)
  check('a big name gets more numbers', #more > 0)
  check('cannot spend what you do not have', not state.addMoney(s, -1e9, 'x', 0) and s.money == progression.START_MONEY)
  check('spending', state.addMoney(s, -500, 'Taxi', 1) and s.money == progression.START_MONEY - 500 and s.ledger[1].label == 'Taxi')
  for i = 1, 100 do state.addMoney(s, 1, 'tick', i) end
  check('the ledger keeps the last 60', #s.ledger == 60)
  state.addMessage(s, 'r01', 'them', 'hi', 1)
  state.addMessage(s, 'r01', 'me', 'yo', 2)
  check('unread counts their messages only', state.unreadCount(s) == 1)
  state.markRead(s, 'r01')
  check('reading clears it', state.unreadCount(s) == 0)
  local car = state.addCar(s, { model = 'covet', name = 'Covet' })
  s.activeCar = car.id
  check('cars get ids', car.id == 1 and state.addCar(s, { model = 'x' }).id == 2)
  state.removeCar(s, 1)
  check('removing the active car clears it', s.activeCar == nil and #s.cars == 1)

  local s2 = state.new(3, 0)
  local racer = s2.racers[1]
  local money0 = s2.money
  local repD, moneyD = state.recordRace(s2, { racer = racer.id, won = true, stake = 'money', bet = 300, night = true, at = 5 })
  check('a recorded win', repD > 0 and moneyD == 300 and s2.money == money0 + 300 and s2.stats.wins == 1 and racer.losses == 1)
  s2.money = 100
  state.recordRace(s2, { racer = racer.id, won = false, stake = 'money', bet = 300, at = 6 })
  check('a loss takes no more than you have', s2.money == 0)
  check('the old save comes back', state.migrate({ seed = 3, money = 5 }).racers ~= nil)
  check('a broken save is refused', state.migrate({}) == nil)
end

-- cars: classes, and making a stock car into the offer
do
  local cars = require('sl/core/cars')
  local configs = {}
  for i = 1, 60 do configs[i] = { model = 'm' .. i, config = 'c' .. i, pw = i / 100, value = i * 1000 } end
  local rng = rngLib.new(11)
  local slow, fast = cars.pickConfig(configs, 'beater', rng), cars.pickConfig(configs, 'super', rng)
  check('a beater is from the slowest sixth', slow.pw <= 0.10, slow.pw)
  check('a supercar is from the fastest sixth', fast.pw > 0.50, fast.pw)
  check('no configs, no car', cars.pickConfig({}, 'sport', rng) == nil)

  local function classify(id)
    local map = { exhaust = { 'engine', 'exhaust' }, radiator = { 'engine', 'cooling' }, tire_FL = { 'running', 'tyres_f' },
      tire_RL = { 'running', 'tyres_r' }, wheel_F = { 'running', 'rims_f' }, bumper_F = { 'body', 'bumpers_f' }, door_FL = { 'body', 'doors' },
      hood = { 'body', 'hoods' }, engine = { 'engine', 'blocks' } }
    local m = map[id] or { 'body', 'misc' }
    return m[1], m[2]
  end
  local function tree()
    local function n(id, part, suitable, children)
      return { id = id, chosenPartName = part, suitablePartNames = suitable or { part }, children = children }
    end
    local root = { chosenPartName = 'car', path = '/', children = {
      engine = n('engine', 'v8', { 'v8' }, { radiator = n('radiator', 'rad', { 'rad', 'rad_race' }), exhaust = n('exhaust', 'exh', { 'exh', 'exh_sport', 'exh_race' }) }),
      tire_FL = n('tire_FL', 'tyre'), tire_RL = n('tire_RL', 'tyre'),
      wheel_F = n('wheel_F', 'steel', { 'steel', 'alloy', 'forged' }),
      bumper_F = n('bumper_F', 'bump'), door_FL = n('door_FL', 'door'), hood = n('hood', 'hood', { 'hood', 'hood_vent' }),
    } }
    local function paths(node, path)
      for id, c in pairs(node.children or {}) do c.path = path .. id .. '/'; paths(c, c.path) end
    end
    paths(root, '/')
    return root
  end
  local values = { exh = 100, exh_sport = 300, exh_race = 600, steel = 50, alloy = 400, forged = 900, rad = 80, rad_race = 200, hood = 100, hood_vent = 250 }
  local function valueOf(p) return values[p] or 0 end

  local t = tree()
  local r = cars.tweakTree(t, { rng = rngLib.new(3), classify = classify, valueOf = valueOf, faults = { 'radiator', 'tyres' }, mods = 0 })
  check('faults take the parts off', t.children.engine.children.radiator.chosenPartName == '' and t.children.tire_FL.chosenPartName == '' and t.children.tire_RL.chosenPartName == '')
  check('faults are listed', #r.removed == 3, #r.removed)
  check('nothing else goes', t.children.engine.chosenPartName == 'v8' and t.children.wheel_F.chosenPartName == 'steel')

  t = tree()
  r = cars.tweakTree(t, { rng = rngLib.new(4), classify = classify, valueOf = valueOf, faults = {}, mods = 2 })
  check('two parts modified', #r.swapped == 2, #r.swapped)
  for _, sw in ipairs(r.swapped) do
    check('a modification is an upgrade ' .. sw.path, valueOf(sw.to) > valueOf(sw.from), sw.from .. ' -> ' .. sw.to)
  end
  t = tree()
  r = cars.tweakTree(t, { rng = rngLib.new(4), classify = classify, valueOf = valueOf, mods = 99 })
  check('no more mods than places to put them', #r.swapped <= 4, #r.swapped)

  local d = cars.dents(tree(), classify, rngLib.new(8), 0.6)
  check('a damaged car has dents', #d >= 1 and #d <= 3, #d)
  for _, x in ipairs(d) do check('dent size in reason ' .. x.partPath, x.dent > 0.005 and x.dent < 0.05, x.dent) end
  check('an undamaged car has none', #cars.dents(tree(), classify, rngLib.new(8), 0) == 0)
end

-- custom builds: street stages and track cars
do
  local builds = require('sl/core/builds')
  local function classify(id)
    local map = { exhaust = { 'engine', 'exhaust' }, intake = { 'engine', 'intake' }, turbo = { 'engine', 'forced' }, wheel_F = { 'running', 'rims_f' },
      seat_R = { 'interior', 'seats_r' }, plate = { 'body', 'plates' }, engine = { 'engine', 'blocks' }, wing = { 'body', 'wings' } }
    local m = map[id] or { 'body', 'misc_keep' }
    return m[1], m[2]
  end
  local function tree()
    local function n(id, part, suitable, children)
      return { id = id, chosenPartName = part, suitablePartNames = suitable or { part }, children = children }
    end
    local root = { chosenPartName = 'car', path = '/', children = {
      engine = n('engine', 'i4', { 'i4' }, {
        exhaust = n('exhaust', 'exh', { 'exh', 'exh_sport', 'exh_race' }),
        intake = n('intake', 'airbox', { 'airbox', 'airbox_sport' }),
        turbo = n('turbo', '', { '', 'turbo_stage1', 'turbo_race' }) }),
      wheel_F = n('wheel_F', 'steel', { 'steel', 'alloy', 'alloy_race' }),
      seat_R = n('seat_R', 'bench'), plate = n('plate', 'plate'),
      wing = n('wing', '', { '', 'wing_street', 'wing_race' }),
    } }
    local function paths(node, path)
      for id, c in pairs(node.children or {}) do c.path = path .. id .. '/'; paths(c, c.path) end
    end
    paths(root, '/')
    return root
  end
  local values = { exh = 100, exh_sport = 300, exh_race = 300, airbox = 50, airbox_sport = 200, turbo_stage1 = 2000, turbo_race = 2500,
    steel = 50, alloy = 400, alloy_race = 380, wing_street = 300, wing_race = 280 }
  local function valueOf(p) return values[p] or 0 end

  check('stage recipes grow', #builds.recipe(1) < #builds.recipe(2) and #builds.recipe(2) < #builds.recipe(3) and #builds.recipe('race') > #builds.recipe(3))
  check('a stock racer has no recipe', #builds.recipe(0) == 0 and builds.stageFor(1) == 0 and builds.stageFor(5) == 3)

  local t = tree()
  local r = builds.apply(t, { stage = 1, classify = classify, valueOf = valueOf })
  check('stage 1: exhaust, intake and wheels', t.children.engine.children.exhaust.chosenPartName ~= 'exh' and t.children.engine.children.intake.chosenPartName == 'airbox_sport'
    and t.children.wheel_F.chosenPartName ~= 'steel', #r.upgraded)
  check('stage 1 leaves the turbo alone', t.children.engine.children.turbo.chosenPartName == '')

  t = tree()
  builds.apply(t, { stage = 3, classify = classify, valueOf = valueOf })
  check('stage 3 adds forced induction and a wing', t.children.engine.children.turbo.chosenPartName ~= '' and t.children.wing.chosenPartName ~= '')
  check('a street build keeps the back seat and plate', t.children.seat_R.chosenPartName == 'bench' and t.children.plate.chosenPartName == 'plate')

  t = tree()
  r = builds.apply(t, { stage = 'race', classify = classify, valueOf = valueOf })
  check('a track car prefers race parts', t.children.engine.children.exhaust.chosenPartName == 'exh_race' and t.children.engine.children.turbo.chosenPartName == 'turbo_race'
    and t.children.wing.chosenPartName == 'wing_race', t.children.engine.children.exhaust.chosenPartName)
  check('a track car loses the back seat and plate', t.children.seat_R.chosenPartName == '' and t.children.plate.chosenPartName == '' and #r.stripped == 2)
  check('nothing outside the recipe changes', t.children.engine.chosenPartName == 'i4')

  local a, b = tree(), tree()
  builds.apply(a, { stage = 3, classify = classify, valueOf = valueOf, rng = rngLib.new(7) })
  builds.apply(b, { stage = 3, classify = classify, valueOf = valueOf, rng = rngLib.new(7) })
  check('the same seed builds the same car', a.children.wheel_F.chosenPartName == b.children.wheel_F.chosenPartName and a.children.wing.chosenPartName == b.children.wing.chosenPartName)
  check('nicknames repeat by seed', builds.nickname(42) == builds.nickname(42) and type(builds.nickname(42)) == 'string')

  -- the drive layout is never changed: a 4WD car keeps its transfer case and 4WD diffs
  local function awdTree()
    return { chosenPartName = 'car', children = {
      transfercase = { id = 'car_transfercase', path = '/tc/', chosenPartName = 'transfercase_4wd', suitablePartNames = { 'transfercase_4wd', 'transfercase_rwd_race' } },
      diff = { id = 'car_differential_R', path = '/d/', chosenPartName = 'diff_R_4wd_open', suitablePartNames = { 'diff_R_4wd_open', 'diff_R_4wd_lsd', 'diff_R_rwd_race_locker' } },
      gearbox = { id = 'car_transmission', path = '/g/', chosenPartName = 'gearbox_5M', suitablePartNames = { 'gearbox_5M', 'gearbox_6M_race' } } } }
  end
  local function classify2(id)
    if id:find('differential') then return 'running', 'differentials' end
    if id:find('transfer') or id:find('transmission') then return 'engine', 'transmission' end
    return 'other', 'other'
  end
  local function value2(name) return (name:find('race') and 9000 or 0) + (name:find('lsd') and 3000 or 0) + 100 end
  local w = awdTree()
  builds.apply(w, { stage = 'race', classify = classify2, valueOf = value2 })
  check('the transfer case is left alone', w.children.transfercase.chosenPartName == 'transfercase_4wd')
  check('a 4WD diff only becomes a better 4WD diff', w.children.diff.chosenPartName == 'diff_R_4wd_lsd', w.children.diff.chosenPartName)
  check('the gearbox is left alone (it can bring another layout with it)', w.children.gearbox.chosenPartName == 'gearbox_5M')
  check('layout words read from names', builds.layoutOf('x_4WD_y') == 'awd' and builds.layoutOf('rwd_race') == 'rwd' and builds.layoutOf('plain') == nil)
  -- a front-drive car: its empty rear diff slot stays empty, and no AWD-only exhaust goes on
  local fwd = { chosenPartName = 'car', children = {
    diffR = { id = 'car_differential_R', path = '/dr/', chosenPartName = '', suitablePartNames = { 'car_differential_R_race' } },
    exh = { id = 'car_exhaust', path = '/e/', chosenPartName = 'exhaust_sport', suitablePartNames = { 'exhaust_sport', 'exhaust_AWD_race', 'exhaust_race' } } } }
  local function classify3(id)
    if id:find('differential') then return 'running', 'differentials' end
    if id:find('exhaust') then return 'engine', 'exhaust' end
    return 'other', 'other'
  end
  builds.apply(fwd, { stage = 'race', classify = classify3, valueOf = function(n) return n:find('AWD') and 20000 or (n:find('race') and 9000 or 100) end })
  check('an empty diff slot stays empty', fwd.children.diffR.chosenPartName == '')
  check('no AWD-only part on a car that is not AWD', fwd.children.exh.chosenPartName == 'exhaust_race', fwd.children.exh.chosenPartName)
  local p = builds.paints(42, false)
  check('three paint slots with colours', #p == 3 and #p[1].baseColor == 4 and p[1].metallic >= 0)

  local cars = {}
  for i = 1, 60 do cars[i] = { model = 'm' .. i, config = 'c' .. i, name = 'Car ' .. i, brand = 'B', value = 5000 * i } end
  local specials = 0
  for day = 1, 15 do
    for _, o in ipairs(market.offers(cars, 'dealer', 3, day, 8)) do
      if o.build == 'race' then
        specials = specials + 1
        check('a track special costs more than the car ' .. o.id, o.price > o.value * 1.4 and o.title == 'Track special')
      end
    end
  end
  check('the dealer sometimes has track specials', specials > 0, specials)
end

-- the showroom: the custom cars kept for testing
do
  local showroom = require('sl/core/showroom')
  local configs = {}
  for i = 1, 120 do configs[i] = { model = 'm' .. (i % 20), config = '/vehicles/m' .. (i % 20) .. '/c' .. i .. '.pc', name = 'Car ' .. i, pw = i / 200, value = 1000 * i } end
  local a, b = showroom.lineup(configs), showroom.lineup(configs)
  check('the lineup is the same for everybody', #a == #b and a[5].file == b[5].file and a[30].config == b[30].config)
  check('4 street cars a class and 3 track cars for the top three classes', #a == 6 * 4 + 3 * 3, #a)
  local seen, track, lowTrack = {}, 0, 0
  for _, e in ipairs(a) do
    local key = e.model .. '/' .. e.file
    check('one file per car ' .. key, not seen[key])
    seen[key] = true
    check('file names are clean ' .. e.file, e.file:match('^street_legal_[a-z0-9_]+$') ~= nil)
    check('a label says what it is ' .. e.label, e.label:find('"', 1, true) and (e.label:find('Stage') or e.label:find('Track')))
    if e.stage == 'race' then
      track = track + 1
      if e.class < 4 then lowTrack = lowTrack + 1 end
    end
    check('a built car is worth more than stock ' .. e.file, e.value > 0)
  end
  check('track cars only from the fast classes', track == 9 and lowTrack == 0)
  check('few configs, a shorter lineup', #showroom.lineup({ configs[1], configs[2] }) <= 2)

end

-- car care: fuel grades, wear, old oil, leaks, the 12 V battery, the trunk
do
  local cc = require('sl_carcare')
  local near = function(a, b) return math.abs(a - b) < 1e-6 end
  check('four fuel grades, premium the reference', #cc.FUELS == 4 and cc.fuel('premium').torque == 1 and cc.fuel('nope').id == 'premium' and cc.fuel(nil).id == 'premium')
  check('better fuel, a little more power', cc.fuel('regular').torque < 1 and cc.fuel('race').torque > cc.fuel('super').torque)
  check('a fresh engine is not worn', cc.wearFactor(0) == 1 and cc.wearFactor(50000) == 1 and cc.wearFactor(nil) == 1)
  check('wear takes some power', cc.wearFactor(200000) < 1 and cc.wearFactor(200000) > 0.88 and near(cc.wearFactor(350000), 0.88) and near(cc.wearFactor(900000), 0.88))
  check('old oil takes a little', cc.oilAgeFactor(5000) == 1 and cc.oilAgeFactor(20000) < 1 and near(cc.oilAgeFactor(60000), 0.95))
  check('low oil takes a little more', cc.oilLevelFactor(1) == 1 and cc.oilLevelFactor(0.6) == 1 and near(cc.oilLevelFactor(0), 0.9) and cc.oilLevelFactor(nil) == 1)
  local p = cc.performance({ engineKm = 0, oilKm = 0, oilLevel = 1, fuel = 'premium' })
  check('a fresh car on premium: full power', p == 1, p)
  local worn = cc.performance({ engineKm = 300000, oilKm = 30000, oilLevel = 0.3, fuel = 'regular' })
  check('a tired car: noticeably less, not crippled', worn < 0.9 and worn > 0.7, worn)
  check('only worn engines leak', cc.leakLitresPerKm(100000) == 0 and cc.leakLitresPerKm(200000) > 0 and cc.leakLitresPerKm(2e6) <= 0.004 + 1e-9)
  local b = cc.battery(1, 600, true, false, false)
  check('ignition on, engine off: the battery runs down', b < 1 and b > 0.5, b)
  check('lights make it worse', cc.battery(1, 600, true, false, true) < b)
  check('the engine charges it', cc.battery(0.5, 60, true, true, false) > 0.5 and cc.battery(0.99, 600, true, true, false) == 1)
  check('switched off, nothing drains', cc.battery(0.8, 600, false, false, false) == 0.8)
  check('flat batteries do not start', not cc.canStart(0.1) and cc.canStart(0.5) and cc.canStart(nil))
  check('a flat battery stays at nothing', cc.battery(0.01, 3600, true, false, true) == 0)
  local trunk = {}
  for i = 1, cc.TRUNK_SLOTS do check('room in the trunk ' .. i, cc.trunkAdd(trunk, 'oil')) end
  local ok, why = cc.trunkAdd(trunk, 'coolant')
  check('a full trunk says so', not ok and why:find('full'))
  check('counting and taking', cc.trunkCount(trunk, 'oil') == cc.TRUNK_SLOTS and cc.trunkTake(trunk, 'oil') and cc.trunkCount(trunk, 'oil') == cc.TRUNK_SLOTS - 1 and not cc.trunkTake(trunk, 'battery'))
  check('unknown things stay out', not cc.trunkAdd({}, 'piano'))
  check('prices', cc.fillCost('race', 10) == 32 and cc.oilChangeCost(4) == 73)
end

-- jobs: part runs and courier parcels
do
  local jobs = require('sl/core/jobs')
  local shops = { { id = 'tyres', name = 'Tyres', x = -700, y = 60 }, { id = 'speed', name = 'Speed', x = 700, y = 470 }, { id = 'near', name = 'Next door', x = -255, y = -1030 } }
  local garage = { id = 'g1', name = 'Garage 1', x = -260, y = -1035 }
  local places = { garage, { id = 'junk', name = 'Junkyard', x = 880, y = -606 }, { id = 'dealer', name = 'Dealer', x = -797, y = 239 }, { id = 'meet', name = 'Meet', x = -121, y = 89 } }
  for seed = 1, 40 do
    local list = jobs.offers(shops, places, garage, rngLib.new(seed), 6)
    check('offers come ' .. seed, #list >= 4)
    for _, j in ipairs(list) do
      check('never next door ' .. seed .. j.id, j.metres >= jobs.MIN_METRES and j.from ~= j.to and j.from ~= 'near')
      check('part runs end at the garage ' .. seed .. j.id, j.kind ~= 'part' or j.to == 'g1')
      check('pay and time ' .. seed .. j.id, j.pay >= jobs.MIN_PAY and j.pay % 10 == 0 and j.seconds >= jobs.MIN_SECONDS)
    end
  end
  local j = { pay = 500, seconds = 300, fragile = false }
  check('on time, clean: full pay', select(1, jobs.settle(j, 200, 0)) == 500 and select(2, jobs.settle(j, 200, 0)) == 'on time')
  check('late: half', jobs.settle(j, 400, 0) == 250 and select(2, jobs.settle(j, 400, 0)) == 'late')
  check('damage docks it', jobs.settle(j, 200, 0.1) == 400 and jobs.settle(j, 200, 1) == 100)
  local f = { pay = 500, seconds = 300, fragile = true }
  check('a fragile load breaks', jobs.settle(f, 200, 0.06) == 0 and select(2, jobs.settle(f, 200, 0.06)) == 'broken' and jobs.settle(f, 200, 0.04) > 0)
  check('nothing to offer, no crash', #jobs.offers({}, {}, nil, rngLib.new(1), 4) == 0)
end

-- show and shine
do
  local ss = require('sl/core/showshine')
  check('clean beats dented', ss.score({ value = 20000, condition = 0.8, dents = 0 }) > ss.score({ value = 20000, condition = 0.8, dents = 200 }))
  check('worth more scores more', ss.score({ value = 40000, condition = 0.5 }) > ss.score({ value = 10000, condition = 1 }))
  check('a wreck still scores', ss.score({ value = 5000, condition = 0.2, dents = 5000 }) > 0)
  check('a fresh wash scores more', ss.score({ value = 20000, condition = 0.8, washed = true }) == math.floor(ss.score({ value = 20000, condition = 0.8 }) * ss.WASHED))
  local rng = rngLib.new(7)
  local low, high = ss.rival(1, rng), ss.rival(5, rng)
  check('better racers, better cars', high > low * 5)
  local place, prize, rep = ss.result(1e9, { 1000, 2000, 3000 })
  check('best car wins', place == 1 and prize > 0 and rep == ss.REP[1])
  local p2, prize2 = ss.result(2500, { 1000, 2000, 3000 })
  check('second pays less', p2 == 2 and prize2 < prize and prize2 > 0)
  local p4, prize4, rep4 = ss.result(1, { 1000, 2000, 3000 })
  check('last pays nothing', p4 == 4 and prize4 == 0 and rep4 == 0)
end

-- the Wrench Works jobs (tools/wwjobs_test.lua)
do
  local dir = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or ''
  assert(loadfile(dir .. 'wwjobs_test.lua'))()(check, rngLib)
  assert(loadfile(dir .. 'listings_test.lua'))()(check, rngLib)      -- the used parts and cars market
end

-- achievements and personal bests
do
  local ach = require('sl/core/achievements')
  local s = { day = 3, rep = 0, money = 3500, cars = {}, stats = { races = 0, wins = 0, pinksWon = 0, pinksLost = 0 } }
  check('nothing earned at the start', #ach.update(s) == 0)
  s.cars = { {}, {}, {} }
  s.stats.wins, s.stats.races = 1, 2
  local got = ach.update(s)
  local ids = {}
  for _, a in ipairs(got) do ids[a.id] = true end
  check('cars and a win earn theirs', ids.first_car and ids.fleet_3 and ids.first_win and ids.first_race and not ids.wins_10)
  check('earned on the day', s.achievements.first_car == 3)
  check('only once', #ach.update(s) == 0)
  check('ids are unique', (function() local seen = {} for _, a in ipairs(ach.LIST) do if seen[a.id] then return false end seen[a.id] = true end return #ach.LIST >= 20 end)())
  check('a first time is a best', ach.best(s, 7, 61.234, 'Night race 7') and s.bests['7'].time == 61.23)
  check('slower is not', not ach.best(s, 7, 70))
  check('faster is', ach.best(s, 7, 58) and s.bests['7'].time == 58)
  check('no time, no best', not ach.best(s, 7, nil) and not ach.best(s, nil, 10))
end

-- the bank: loans that can't spiral, insurance that can't be gamed
do
  local bank = require('sl/core/bank')
  check('loan limits grow with rep, capped', bank.loanLimit(0) == 3000 and bank.loanLimit(1500) == 6000 and bank.loanLimit(1e6) == 20000)
  local loan = bank.newLoan(5000, 10)
  for _ = 1, 100 do bank.accrue(loan) end
  check('owed never passes 1.5x', loan.owed == 7500)
  check('due is a quarter', bank.due(loan) == 1875)
  local r1 = bank.payment(loan, 0)
  local r2 = bank.payment(loan, 0)
  local r3 = bank.payment(loan, 0)
  check('two warnings before repossession', r1 == 'warning' and r2 == 'final' and r3 == 'repossess')
  loan = bank.newLoan(1000, 1)
  local r, paid = bank.payment(loan, 5000)
  check('a payment pays a quarter', r == 'paid' and paid == 250 and loan.owed == 750 and loan.missed == 0)
  bank.payment(loan, 0)
  bank.payment(loan, 5000)
  check('paying resets the warnings', loan.missed == 0)
  local small = bank.newLoan(150, 1)
  check('the minimum is $100, never more than owed', bank.due(small) == 100 and bank.due({ owed = 60 }) == 60)
  local policy = { active = true, from = 5 }
  check('no cover before it starts', bank.claim(policy, 2000, 4) == 0)
  check('half over the deductible', bank.claim(policy, 2200, 5) == 1000)
  check('small claims pay nothing', bank.claim(policy, 150, 9) == 0)
  check('no policy, no payout', bank.claim(nil, 5000, 9) == 0 and bank.claim({ active = false, from = 0 }, 5000, 9) == 0)
  check('premium by fleet value', bank.premium(0) == 100 and bank.premium(20000) == 400)
end

-- clubs, leagues and the season (X20/X5)
do
  local clubs = require('sl/core/clubs')
  check('classes by PS per tonne', clubs.classOf(100, 1300) == 'D' and clubs.classOf(150, 1300) == 'C' and clubs.classOf(220, 1300) == 'B'
    and clubs.classOf(300, 1300) == 'A' and clubs.classOf(500, 1300) == 'S')
  local roster = {}
  for i = 1, 30 do roster[i] = { id = 'r' .. i, tier = (i % 5) + 1, skill = 0.2 + (i % 5) * 0.15 } end
  local m1 = clubs.members(roster, 1)
  check('club 1 has tiers 1-2 only', #m1 > 0 and (function() for _, r in ipairs(m1) do if r.tier > 2 then return false end end return true end)())
  local races = {}
  for i = 1, 18 do races[#races + 1] = { id = i, missionId = 'n' .. i, name = 'Night ' .. i, kind = 'night' } end
  for i = 1, 5 do races[#races + 1] = { id = 'v' .. i, missionId = 'v' .. i, name = 'Venue ' .. i, kind = 'venue' } end
  local cal = clubs.calendar(races, rngLib.new(4))
  local nights, ok = {}, true
  for d = 1, clubs.SEASON_DAYS do
    if not cal[d].night or not cal[d].day then ok = false end
    if cal[d].night then if nights[cal[d].night.id] then ok = false end nights[cal[d].night.id] = true end
  end
  check('a week of events, no night race twice', ok and cal[7].finale and not cal[1].finale)
  check('points, doubled at the finale', clubs.points(1) == 10 and clubs.points(1, true) == 20 and clubs.points(9) == 1 and clubs.points(nil) == 0)
  -- the faster driver wins more often (and the player can be slotted in); seeded as the game seeds it (a hash)
  local fast, slow = { id = 'fast', skill = 0.9 }, { id = 'slow', skill = 0.3 }
  local wins = 0
  for seed = 1, 200 do if clubs.simulate({ fast, slow }, rngLib.new(rngLib.hash('ev' .. seed)))[1] == 'fast' then wins = wins + 1 end end
  check('a better driver wins most, not all', wins > 180)
  local mid = { id = 'mid', skill = 0.55 }
  local upsets = 0
  for seed = 1, 400 do if clubs.simulate({ mid, { id = 'b', skill = 0.6 } }, rngLib.new(rngLib.hash('ev' .. seed)))[1] == 'mid' then upsets = upsets + 1 end end
  check('close drivers trade wins (the slower one 10-50 %)', upsets > 40 and upsets < 200)
  local order = clubs.simulate({ fast, slow }, rngLib.new(1), 2)
  check('the player takes their place', order[2] == 'player' and #order == 3)
  local st = clubs.score({}, { 'a', 'player', 'b' })
  check('standings', st.a == 10 and st.player == 6 and st.b == 4 and clubs.placeOf(st, 'player') == 2)
  check('skipping costs nothing but points', clubs.score(st, { 'a', 'b' }).player == 6)
  local money, rep, invited = clubs.seasonReward(2, 1)
  check('a champion is paid and invited', money == 3000 and rep == 250 and invited)
  check('4th gets nothing', select(1, clubs.seasonReward(2, 4)) == 0 and not select(3, clubs.seasonReward(2, 4)))
  check('purse by place', clubs.purse(1, 1) == 300 and clubs.purse(1, 2) == 150 and clubs.purse(1, 4) == 0)
end

-- leaving a lot by the road (playtest: boxed-in display spots)
do
  local rs = require('sl/core/roadspot')
  local function P(x, y) return { x = x, y = y, z = 0 } end
  local function link(i, o, extra) local e = { inNode = i, outNode = o, drivability = 1, speedLimit = 14, lanes = '-+' } for k, v in pairs(extra or {}) do e[k] = v end return e end
  -- a street along x (a..d), a freeway (f1..f3) closer to the lot, a junction at b
  local nodes = {
    a = { pos = P(0, 0), radius = 4, links = {} }, b = { pos = P(50, 0), radius = 4, links = {} },
    c = { pos = P(100, 0), radius = 4, links = {} }, d = { pos = P(150, 0), radius = 4, links = {} },
    s = { pos = P(50, 60), radius = 4, links = {} },
    f1 = { pos = P(0, 20), radius = 6, links = {} }, f2 = { pos = P(60, 20), radius = 6, links = {} }, f3 = { pos = P(120, 20), radius = 6, links = {} },
  }
  local function connect(i, o, extra) nodes[i].links[o] = link(i, o, extra) nodes[o].links[i] = link(i, o, extra) end
  connect('a', 'b') connect('b', 'c') connect('c', 'd') connect('b', 's')
  connect('f1', 'f2', { speedLimit = 30 }) connect('f2', 'f3', { speedLimit = 30 })
  nodes.a.links.z = link('a', 'z') nodes.z = { pos = P(-50, 0), radius = 4, links = { a = link('a', 'z') } }
  nodes.y = { pos = P(200, 0), radius = 4, links = {} } nodes.w = { pos = P(250, 0), radius = 4, links = {} }
  connect('d', 'y') connect('y', 'w') nodes.w.links.v = link('w', 'v')
  local c = rs.candidates(nodes, P(120, 25), true)
  check('road spot: never the freeway, never at a junction', #c > 0 and c[1].y < 5)
  check('road spot: the nearest plain link, its middle', math.abs(c[1].x - 125) < 0.01)
  check('road spot: in the right-hand lane, facing along it', math.abs(math.abs(c[1].y) - 2) < 0.01 and math.abs(c[1].dx) == 1 and (c[1].dx > 0) == (c[1].y < 0))
  local free = rs.pick(c, { P(125, -2) })
  check('road spot: skips one with a car on it', free and math.abs(free.x - 125) > 1)
  -- Valo City's real navgraph: one node per lane, radius 1.75, one-way links with inNode/outNode (no spot was found anywhere at 2.4)
  do
    local function lane(i, o) return { inNode = i, outNode = o, drivability = 1, speedLimit = 16.7, lanes = '+', oneWay = true } end
    local ns = { l1 = { pos = P(0, 0), radius = 1.75, links = {} }, l2 = { pos = P(40, 0), radius = 1.75, links = {} }, l3 = { pos = P(80, 0), radius = 1.75, links = {} }, l4 = { pos = P(120, 0), radius = 1.75, links = {} } }
    ns.l1.links.l2 = lane('l1', 'l2') ns.l2.links.l1 = ns.l1.links.l2
    ns.l2.links.l3 = lane('l3', 'l2') ns.l3.links.l2 = ns.l2.links.l3      -- (seen from l2's side: the far node is the inNode)
    ns.l3.links.l4 = lane('l3', 'l4') ns.l4.links.l3 = ns.l3.links.l4
    local c = rs.candidates(ns, P(60, 10), true)
    check('road spot: a 1.75 m one-way lane counts, lane ends too (B35/B36: 17,174 of Valo City's 19,339 lane nodes have one link)', #c == 3)
    check('road spot: a one-way lane is faced the way it runs', c[1] and c[1].x == 60 and c[1].dx == -1 and math.abs(c[1].y) < 0.01)
  end
  check('road spot: hidden and private roads are not city lanes', #rs.candidates({ a = { pos = P(0, 0), radius = 4, links = { b = link('a', 'b', { type = 'private' }) } },
    b = { pos = P(50, 0), radius = 4, links = { a = link('a', 'b', { type = 'private' }) } } }, P(0, 0), true) == 0)
end


-- rival crews and their districts (X21, Design 6)
do
  local crews = require('sl/core/crews')
  local racers = roster.generate(7, 36)
  local member, leader = crews.assign(racers, rngLib.new(3))
  local count, top = {}, {}
  for _, r in ipairs(racers) do
    local c = member[r.id]
    count[c] = (count[c] or 0) + 1
    if r.tier == 5 then top[c] = true end
  end
  check('every racer in a crew, the crews even', count.southside == 9 and count.riverbed == 9 and count.northend == 9 and count.ringroad == 9)
  check('each crew has a leader of its own', member[leader.southside] == 'southside' and member[leader.ringroad] == 'ringroad')
  local pts = {}
  for i = 1, 60 do local a = i / 60 * math.pi * 2 pts[#pts + 1] = { x = math.cos(a) * (200 + i % 7 * 60), y = math.sin(a) * (200 + i % 5 * 70) } end
  for i = 1, 10 do pts[#pts + 1] = { x = i * 3, y = -i * 2 } end
  local ds = crews.cluster(pts, 6)
  local names = {}
  for _, d in ipairs(ds) do names[d.name] = true end
  check('six districts from the places, one Downtown, the rest by the compass', #ds == 6 and names.Downtown)
  check('a place is in the district nearest it', crews.districtOf(ds, ds[2].centre.x, ds[2].centre.y).id == ds[2].id)
  local square = { { id = 'sq', name = 'Square', polygon = { { 0, 0 }, { 100, 0 }, { 100, 100 }, { 0, 100 } } }, { id = 'far', name = 'Far', centre = { x = 500, y = 500 } } }
  check('inside a polygon wins over a nearer centre', crews.districtOf(square, 90, 90).id == 'sq' and crews.districtOf(square, 300, 300).id == 'far')
  local t = crews.newTerritory(ds, rngLib.new(5))
  local homes, owned = 0, {}
  for _, d in pairs(t) do if d.home then homes = homes + 1 end owned[d.owner] = true end
  check('every crew holds its home, every district has an owner', homes == 4 and owned.southside and owned.riverbed and owned.northend and owned.ringroad)
  local id, d0
  for k, d in pairs(t) do if not d.home then id, d0 = k, d end end
  local owner = d0.owner
  crews.raceResult(t, id, 'nobody', false, true)
  check('beating a crew that does not hold it changes nothing', t[id].owner == owner and t[id].control == crews.START_CONTROL)
  crews.raceResult(t, id, owner, false, false)
  check('a race lost gives them some back', t[id].control == crews.START_CONTROL + crews.LOSS)
  crews.raceResult(t, id, owner, false, true)
  crews.raceResult(t, id, owner, false, true)
  local _, ev = crews.raceResult(t, id, owner, true, true)
  check('beaten on their own streets, the district is yours', ev == 'taken' and t[id].owner == 'player' and t[id].control == crews.TAKEN_CONTROL)
  check('and its perks with it', crews.perks(t, id).rep > 1 and crews.perks(t, id).heat < 1)
  crews.raceResult(t, id, owner, false, false)
  local _, ev2 = crews.raceResult(t, id, owner, false, false, true)
  check('lose there often enough and it goes back', ev2 == 'lost' and t[id].owner == owner)
  local friendly = crews.raceResult(t, id, owner, true, true, false, owner)
  check('racing a crew you work for takes nothing from it', friendly.owner == owner)
  for seed = 1, 200 do crews.nightly(t, rngLib.new(seed)) end
  local homesOk = true
  for _, d in pairs(t) do if d.home and d.owner ~= d.home then homesOk = false end end
  check('the crews trade districts at night, never a home', homesOk)
  check('the turf war waits for enough districts', not crews.turfWarReady(t))
  local n = 0
  for _, d in pairs(t) do if n < crews.TURF_WAR_AT then d.owner, n = 'player', n + 1 end end
  check('then the leaders come', n == crews.TURF_WAR_AT and crews.turfWarReady(t))
end

print(string.format('lua tests passed: %d checks', passed))
