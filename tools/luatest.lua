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
    r = roster.respond(pinkOK, 'pink', { rep = 0, money = 0, hasCar = true }, rng)
    check('pink slips with somebody who races for cars', r.accept and r.stake == 'pink' and r.bet == 0)
  end
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

print(string.format('lua tests passed: %d checks', passed))
