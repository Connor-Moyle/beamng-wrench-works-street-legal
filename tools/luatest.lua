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
  check('scrap pays less than a private buyer', market.scrapValue({ value = 20000, condition = 0.5 }) < market.resaleValue({ value = 20000, condition = 0.5 }))
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

print(string.format('lua tests passed: %d checks', passed))
