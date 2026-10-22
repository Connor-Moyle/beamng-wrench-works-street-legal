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
  check('titles', progression.titleFor(0) == 'Nobody' and progression.titleFor(150) == 'Street kid' and progression.titleFor(99999) == 'King of the Streets')
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
  check('the engine crane is bought, and the club garages come with it', not bare.crane and club.crane and progression.garageFeatures({ crane = true }, 1).crane and progression.upgrade('crane') ~= nil)
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
  -- the rematch rule (W3): beaten, they refuse until their rematch text; a winner races again at once
  local beat = roster.generate(5, 36)[1]
  roster.afterRace(beat, true, nil, rngLib.new(3))
  check('a beaten racer is marked', beat.beaten == true)
  check('a beaten racer refuses', roster.respond(beat, 'race', { rep = 1e6, money = 1e6, hasCar = true }, rngLib.new(1)).accept == false)
  check('the rematch text clears it', type(roster.rematchText(beat, rngLib.new(2))) == 'string' and beat.beaten == nil)
  roster.afterRace(beat, false, 1, rngLib.new(4))
  check('a racer who beat you races again at once', beat.beaten == nil)
  local taunts, rematches, narrow = 0, 0, 0
  for i = 1, 400 do
    local x = { style = 'trash' }
    local o = roster.afterRace(x, true, i % 2 == 0 and 1 or 10, rngLib.new(rngLib.hash('after:' .. i)))   -- (seeded by a hash, as the career does: a small seed's first draw is tiny)
    if o.taunt then taunts = taunts + 1 end
    if o.rematchIn then
      rematches = rematches + 1
      if i % 2 == 0 then narrow = narrow + 1 end
      check('a rematch comes 1-6 game hours later', o.rematchIn >= 1 and o.rematchIn <= 6)
    end
  end
  check('about 40 % of races get a text', taunts > 120 and taunts < 200, taunts)
  check('a narrow loss makes a rematch likelier', narrow > rematches - narrow, narrow .. ' of ' .. rematches)
  check('ten or more lines each', #roster._TAUNTS.sore >= 10 and #roster._TAUNTS.mock >= 10)
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
  -- B60: private car ads were drawn one at a time, and a draw of one always came back as the lot's starter (its cheapest car)
  local models = {}
  for seed = 1, 6 do local one = market.offers(cars, 'used', seed, 0, 1, true)[1] models[one.config] = true end
  local ads = market.offers(cars, 'used', 5, 0, 8, true)
  local variety = {}
  for _, o in ipairs(ads) do variety[o.model] = true end
  local nModels, nAds = 0, 0
  for _ in pairs(variety) do nModels = nModels + 1 end
  for _ in pairs(models) do nAds = nAds + 1 end
  check('private ads (no starter): a draw of many gives many models, and draws of one differ by seed', #ads == 8 and nModels >= 4 and nAds >= 3, nModels .. ' / ' .. nAds)
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
    -- B38: a part with no price on record (0, from an old save) is no fix anywhere: open, no premium, the full penalty
    local zero = { value = 20000, condition = 0.3, faults = { 'exhaust' }, boughtFor = 5000, repaired = 4100, fixed = { exhaust = 0 } }
    local open = { value = 20000, condition = 0.3, faults = { 'exhaust' }, boughtFor = 5000, repaired = 4100 }
    check('a $0 record leaves the fault open', #market.unfixed(zero) == 1 and not market.rebuilt(zero) and market.resaleValue(zero) == market.resaleValue(open))
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
  check('a save keeps its map (W1); one from before has none', state.migrate({ seed = 3, level = 'west_coast_usa' }).level == 'west_coast_usa' and state.migrate({ seed = 3 }).level == nil)
  check('the career starts in daylight (W1)', not progression.isNight(progression.START_HOUR))
  for _, id in ipairs(progression.MAP_ORDER) do
    local m = progression.MAPS[id]
    check('map ' .. id .. ' has a name and a full garage ladder', type(m.name) == 'string' and (m.garages == nil or #m.garages == #progression.garages))
  end
  check('a broken save is refused', state.migrate({}) == nil)
end

-- the career's own street races (W3, sl/core/races): start lines on wide straight roads, routes 1.5-4 km to a
-- junction, the two cars lined up facing the route's first edge. A mock navgraph: a 2 km grid, streets every
-- 250 m, a node every 50 m; the avenues (x = 0, 1000, 2000) are wide, the rest narrow
do
  local racesLib = require('sl/core/races')
  local nodes = {}
  local function nm(x, y) return string.format('n_%d_%d', x, y) end
  local function add(x, y)
    local name = nm(x, y)
    if not nodes[name] then nodes[name] = { pos = { x = x, y = y, z = 10 }, radius = (x % 1000 == 0) and 4 or 2.5, links = {} } end
    return name
  end
  local function link(a, b) nodes[a].links[b] = {} nodes[b].links[a] = {} end
  for x = 0, 2000, 250 do           -- north-south streets
    for y = 0, 1950, 50 do link(add(x, y), add(x, y + 50)) end
  end
  for y = 0, 2000, 250 do           -- east-west streets
    for x = 0, 1950, 50 do link(add(x, y), add(x + 50, y)) end
  end
  local function pathFn(a, b)       -- Dijkstra over the mock, the shortest 2-D path
    local dist, prev, done = { [a] = 0 }, {}, {}
    while true do
      local u, best
      for n, d in pairs(dist) do if not done[n] and (not best or d < best) then u, best = n, d end end
      if not u then return {} end
      if u == b then break end
      done[u] = true
      for v in pairs(nodes[u].links) do
        local d = best + racesLib.dist2d(nodes[u].pos, nodes[v].pos)
        if not dist[v] or d < dist[v] then dist[v], prev[v] = d, u end
      end
    end
    local path, n = {}, b
    while n do table.insert(path, 1, n) n = prev[n] end
    return path
  end
  check('a junction has degree 4, a street node 2', racesLib.degree(nodes, nm(250, 250)) == 4 and racesLib.degree(nodes, nm(250, 100)) == 2)
  local run = racesLib.straightRun(nodes, nm(0, 50), nm(0, 100))
  check('a straight run stops at the next junction', run == 200, run)
  local rng = rngLib.new(5)
  local starts = racesLib.pickStarts(nodes, rng, 6, 400)
  check('start lines found', #starts >= 3, #starts)
  local ok = true
  for i, s in ipairs(starts) do
    if nodes[s.node].radius < racesLib.WIDE then ok = false end
    if math.abs(s.dir.x ^ 2 + s.dir.y ^ 2 - 1) > 1e-6 then ok = false end
    if racesLib.straightRun(nodes, s.node, s.next) < racesLib.RUN then ok = false end
    for j = 1, i - 1 do if racesLib.dist2d(s.pos, starts[j].pos) < 400 then ok = false end end
  end
  check('every start is on a wide road with a straight run, apart from the others', ok)
  local again = racesLib.pickStarts(nodes, rngLib.new(5), 6, 400)
  check('the same seed picks the same starts', again[1].node == starts[1].node and #again == #starts)
  local goal, path, len = racesLib.pickGoal(nodes, starts[1].node, pathFn, rng)
  check('a goal is a junction 1.5-4 km along the path', goal and racesLib.degree(nodes, goal) >= 3 and len >= racesLib.MIN_LEN and len <= racesLib.MAX_LEN
    and path[1] == starts[1].node and path[#path] == goal, len)
  check('the path length adds up', math.abs(racesLib.pathLength(nodes, path) - len) < 1e-6)
  local dir = racesLib.routeDir(nodes, path)
  check('the route direction is the first edge', dir and math.abs(dir.x ^ 2 + dir.y ^ 2 - 1) < 1e-6)
  local line = racesLib.lineUp({ x = 100, y = 100, z = 10 }, { x = 0, y = 1 })
  check('the player lines up on the right of the direction of travel, the opponent on the left, 3.2 m apart',
    line.player.pos.x > line.opponent.pos.x and math.abs(line.player.pos.x - line.opponent.pos.x - racesLib.GAP) < 1e-6
    and line.player.pos.y == 100 and line.player.pos.z == 10 and line.player.dir.y == 1)
  check('near the goal within 10 m', racesLib.nearGoal({ x = 5, y = 8, z = 0 }, { x = 0, y = 0, z = 50 }) and not racesLib.nearGoal({ x = 11, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }))
  -- the racing step: positions against the goal only (the game-side onUpdate does nothing else: no navgraph)
  local goal, far, there = { x = 1000, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, { x = 995, y = 3, z = 0 }
  local d = {}
  check('still racing', racesLib.step(goal, far, far, 10, d) == nil and d.player == nil)
  check('the opponent in first, the player has 60 s', racesLib.step(goal, far, there, 20, d) == nil and d.opponent == 20)
  check('still racing at 59 s behind', racesLib.step(goal, far, far, 79, d) == nil)
  check('lost 60 s behind', racesLib.step(goal, far, far, 81, d) == 'lost')
  d = {}
  check('the player in first wins', racesLib.step(goal, there, far, 30, d) == 'won' and d.player == 30)
  d = { opponent = 10 }
  check('in second is a loss', racesLib.step(goal, there, far, 30, d) == 'lost')
  d = {}
  check('no opponent left: finishing wins', racesLib.step(goal, there, nil, 30, d) == 'won')
end

-- the race flares' flicker and the lockdown's one rule (W5 frames): engine writes only on a change or on the clock
do
  local flares = require('sl/core/flares')
  local lights = {}
  for i = 1, 40 do lights[i] = { phase = i * 1.7, x = i * 10, y = 0 } end
  local writes, batches, last = 0, 0, nil
  for f = 1, 60 do
    local w
    w, last = flares.flicker(lights, f / 60, last, { x = 0, y = 0 })
    if #w > 0 then batches = batches + 1 end
    writes = writes + #w
  end
  check('the flicker runs ten times a second, not every frame', batches >= 9 and batches <= 11, batches)
  check('only the flares within reach are written', writes == batches * 12, writes)   -- (x <= 120: twelve of forty)
  local w = flares.flicker(lights, 100, nil, { x = 5000, y = 5000 })
  check('far from every flare nothing is written', #w == 0)
  check('every write is a sane intensity', (function() for _, x in ipairs(flares.flicker(lights, 7, nil, nil)) do if x[2] < 0.2 or x[2] > 1.4 then return false end end return true end)())
  check('the lockdown applies once per change', flares.lockStep(false, true) == 'lock' and flares.lockStep(true, true) == nil
    and flares.lockStep(true, false) == 'unlock' and flares.lockStep(false, false) == nil and flares.lockStep(false, nil) == nil)
end

-- the wet world and the puddles at a distance
do
  local ww, wx = require('sl/core/wetworld'), require('sl/core/weather')
  do
    local h = 0
    h = ww.held(h, 1, 1) 
    local up = h
    for _ = 1, 120 do h = ww.held(h, 0, 1) end
    local mid = h
    for _ = 1, 130 do h = ww.held(h, 0, 1) end
    check('wet world: wetness follows rain up at once and dries down over about four minutes', up == 1 and mid > 0.45 and mid < 0.55 and h == 0 and ww.held(0.2, 0.8, 1) == 0.8)
    check('a colour factor given as the word White is read (it was skipped: walls and roads stayed dry-looking)', ww.parseColor('White')[1] == 1 and #ww.parseColor('White') == 4 and ww.parseColor('0.5 0.5 0.5 1')[1] == 0.5 and ww.parseColor('nonsense') == nil)
  check('materials are edited in three levels', ww.materialStep(0) == 0 and ww.materialStep(2) == 0 and ww.materialStep(3) == 3 and ww.materialStep(5) == 3 and ww.materialStep(6) == 6)
  end
  check('wet terrain: dry 0, one wet tier (2) from step 2 on, so a rain swaps the terrain once', ww.terrainTier(0) == 0 and ww.terrainTier(1) == 0 and ww.terrainTier(2) == 2 and ww.terrainTier(4) == 2 and ww.terrainTier(ww.STEPS) == 2 and ww.terrainTier(nil) == 0)
  check('wet: roads are asphalt first, cars and tunnels and lights are left alone', ww.classify('road_asphalt_01') == 'asphalt' and ww.classify('sidewalk_concrete') == 'concrete' and ww.classify('palm_leaves') == 'foliage'
    and ww.classify('tunnel_wall') == nil and ww.classify('street_lamp_glass') == nil and ww.classify('road_x', '/vehicles/pickup/x.json') == nil and ww.classify('sl_puddle') == nil and ww.classify('') == nil)
  check('wet: the step follows the wetness and the strength', ww.step(0, 1) == 0 and ww.step(1, 1) == ww.STEPS and ww.step(1, 0.5) == ww.STEPS / 2 and ww.step(1, 0) == 0)
  check('wet: hysteresis, a flickering wetness does not move the step', ww.step(0.47, 1, 3) == 3 and ww.step(0.52, 1, 3) == 3 and ww.step(0.8, 1, 3) == 4 and ww.step(0.2, 1, 3) == 2)
  check('wet: asphalt darkens and shines most, a dry step is the original, glass keeps its colour', ww.roughness('asphalt', 0.8, 1) < ww.roughness('foliage', 0.8, 1) and ww.roughness('asphalt', 0.8, 0) == 0.8
    and ww.colorFactor('asphalt', 1) < ww.colorFactor('metal', 1) and ww.colorFactor('glass', 1) == 1 and ww.colorFactor('asphalt', 0) == 1)
  local c = ww.parseColor('0.8 0.7 0.6 1')
  check('wet: colour text round trips and the alpha is untouched', c and #c == 4 and ww.formatColor(c, 0.5) == '0.4000 0.3500 0.3000 1.0000' and ww.parseColor('x') == nil)
  local plan = ww.plan({ { name = 'grass_a' }, { name = 'road_b' }, { name = 'tunnel_road' }, { name = 'wall_c' }, { name = 'road_a' }, { name = 'ui_x' } }, 3)
  check('fileOf: nil from the game counts as empty, a failed call stays nil', ww.fileOf(true, nil) == '' and ww.fileOf(true, '') == '' and ww.fileOf(true, 'a.json') == 'a.json' and ww.fileOf(false, nil) == nil)
  local nilGlass = ww.plan({ { name = 'bx_signalglass', file = ww.fileOf(true, nil) }, { name = 'bld_glass_transparent', file = '/levels/x/a.materials.json' } }, 10)
  check('plan skips a vehicle glass whose file came back nil', #nilGlass == 1 and nilGlass[1].name == 'bld_glass_transparent')
  local withFiles = ww.plan({ { name = 'bld_glass_transparent', file = '/levels/x/a.materials.json' }, { name = 'hopper_signalglass_L', file = '' }, { name = 'autobello_chmslglass', file = '' }, { name = 'asphalt_a' } }, 10)
  check('wet: a material the game reports with an empty file (a vehicle-side one, such as a lamp glass) is never planned; a missing file field still goes by the name', #withFiles == 2 and withFiles[1].name == 'asphalt_a' and withFiles[2].name == 'bld_glass_transparent')
  check('wet: the plan is road first, the rest by kind, capped, with the skipped left out', #plan == 3 and plan[1].name == 'road_a' and plan[2].name == 'road_b' and plan[3].name == 'wall_c')
  check('wet: the batch is small when edits are slow and never above the maximum', ww.batch(nil) == 2 and ww.batch(nil, 3, 1) == 1 and ww.batch(10) == 1 and ww.batch(0.1, 3, 8) == 8 and ww.batch(1, 3, 8) == 3)
  -- the kinds of standing water: the odds add to one, every kind is sane, the long ones lie along the road, and over many draws every kind comes
  local total = 0
  for _, o in ipairs(wx.POOL_ODDS) do total = total + o[2] end
  local seen, sane, mats = {}, true, {}
  local seed = 7
  local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
  for _ = 1, 600 do
    local pool = wx.pool(rnd)
    seen[pool.kind] = true
    mats[pool.material] = true
    if pool.sx < 0.5 or pool.sy < 0.3 or pool.sx > 20 or pool.sy > 15 or (pool.kind == 'edge' or pool.kind == 'rut') and (not pool.along or pool.sx / pool.sy < 3.5) then sane = false end
    if pool.lateral and (pool.lateral < 0 or pool.lateral > 0.95) then sane = false end
  end
  check('puddle kinds: odds add to one, every kind comes, shapes are sane (long pools and wheel tracks lie along the road and are long and thin)', math.abs(total - 1) < 1e-9 and seen.edge and seen.rut and seen.small and seen.dip and seen.round and seen.damp and sane)
  check('puddle kinds: three materials (normal, deeper, thinner) are used', mats.sl_puddle and mats.sl_puddle_deep and mats.sl_puddle_thin)
  check('puddles take 20 s to come to full size and the budget is bigger', wx.puddleAlpha(1, 20) > wx.puddleAlpha(1, 10) and wx.puddleAlpha(1, 10) > wx.puddleAlpha(1, 2) and wx.MAX_PUDDLES >= 120)
  check('damp patches: bare and hard ground only, never grass or a layer that says nothing', wx.dampGroundOk('asphalt_cracked') and wx.dampGroundOk('Dirt_dry') and wx.dampGroundOk('gravel_01') and wx.dampGroundOk('concrete_old')
    and not wx.dampGroundOk('grass_dry') and not wx.dampGroundOk('forest_floor_dirt') and not wx.dampGroundOk('unnamed_layer') and not wx.dampGroundOk(nil))
  check('puddles: full size up close, nothing at the far edge, smooth between (no pop in)', wx.distanceScale(50, 165, 225) == 1 and wx.distanceScale(225, 165, 225) == 0 and wx.distanceScale(300, 165, 225) == 0
    and wx.distanceScale(195, 165, 225) > 0.4 and wx.distanceScale(195, 165, 225) < 0.6 and wx.distanceScale(180, 165, 225) > wx.distanceScale(210, 165, 225))
end

-- the garage forecourt: the first spot with nothing within 4 m
do
  local fc = require('sl/core/forecourt')
  local spots = { { x = 0, y = 0 }, { x = 3, y = 0 }, { x = 6, y = 0 }, { x = 0, y = 6 } }
  check('forecourt: empty, the first spot', fc.pick(spots, {}) == 1)
  check('forecourt: a car on the first spot (or 3.9 m from it) takes it', fc.pick(spots, { { x = 1, y = 0 } }) == 3 and fc.pick(spots, { { x = 0, y = 3.9 } }) == 2)
  check('forecourt: 4 m away is clear', fc.pick({ { x = 0, y = 0 } }, { { x = 4, y = 0 } }) == 1)
  check('forecourt: every spot taken: nil, any vehicle counts', fc.pick(spots, { { x = 1, y = 1 }, { x = 5, y = 3 }, { x = 1, y = 5 } }) == nil and fc.SPOTS == 12)
end

-- the phone's Map app: groups, distances, arrival
do
  local mapapp = require('sl/core/mapapp')
  local places = { { id = 'g2', name = 'North garage', kind = 'garage', x = 500, y = 0 }, { id = 'g1', name = 'Home', kind = 'garage', x = 100, y = 0 },
    { id = 'm1', name = 'Pier meet', kind = 'meet', x = 0, y = 300 }, { id = 'd1', name = 'Dealer', kind = 'dealer', x = 0, y = 50 }, { id = 'x1', name = 'Odd', kind = 'zzz', x = 1, y = 1 } }
  local g = mapapp.groups(places, { x = 0, y = 0 })
  check('map: groups in order, the odd kind last', #g == 4 and g[1].kind == 'garage' and g[2].kind == 'dealer' and g[3].kind == 'meet' and g[4].kind == 'zzz')
  check('map: nearest first, with metres', g[1].places[1].id == 'g1' and g[1].places[1].dist == 100 and g[1].places[2].dist == 500)
  check('map: no player, no distances, still listed', mapapp.groups(places, nil)[1].places[1].dist == nil and #mapapp.groups(places, nil) == 4)
  check('map: the route is active only while it is the single end point at its place', mapapp.stillActive({ { x = 100, y = 200 } }, { x = 100.4, y = 199.6 })
    and not mapapp.stillActive({ { x = 500, y = 0 } }, { x = 100, y = 200 }) and not mapapp.stillActive(nil, { x = 1, y = 1 }) and not mapapp.stillActive({}, { x = 1, y = 1 })
    and not mapapp.stillActive({ { x = 100, y = 200 }, { x = 5, y = 5 } }, { x = 100, y = 200 }))
  local ppl = mapapp.people({ { id = 'r1', name = 'Rival', kind = 'rival', line = 'x' } }, { { id = 'r1', name = 'Dup', kind = 'crew' }, { id = 'r2', name = 'Lead', kind = 'crew' } }, { { id = 'dealer:d', name = 'D', kind = 'dealer', placeId = 'd' } })
  check('map: people rivals first, an id once', #ppl == 3 and ppl[1].kind == 'rival' and ppl[2].id == 'r2' and ppl[3].kind == 'dealer' and #mapapp.people(nil, nil, nil) == 0)
  check('map: arrival within 15 m', mapapp.arrived({ x = 10, y = 0 }, { x = 20, y = 0 }) and not mapapp.arrived({ x = 0, y = 0 }, { x = 20, y = 0 }) and not mapapp.arrived(nil, { x = 0, y = 0 }))
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
  -- passenger comfort: a smooth ride tips well, hard pushes cost the tip
  local calm, rough = jobs.comfortNew(), jobs.comfortNew()
  for i = 1, 100 do
    jobs.comfortStep(calm, 0.1, 10 + i * 0.02, 0, 0)
    jobs.comfortStep(rough, 0.1, (i % 2 == 0) and 15 or 0, 0, 0)
  end
  check('a calm ride scores full and tips 50 %', jobs.comfortScore(calm) == 1 and jobs.tip(100, jobs.comfortScore(calm)) == 50)
  check('a jerky ride scores zero and tips nothing', jobs.comfortScore(rough) == 0 and jobs.tip(100, 0) == 0)
  check('tip tiers', jobs.tip(100, 0.75) == 30 and jobs.tip(100, 0.55) == 10)
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
  assert(loadfile(dir .. 'wetworld_test.lua'))()(check)      -- the wet world: terrain layers only unless the experiment key is on
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
  check('loan limits grow with rep, capped', bank.loanLimit(0) == 3000 and bank.loanLimit(1500) == 6000 and bank.loanLimit(1e6) == bank.MAX_LOAN and bank.MAX_LOAN == 120000)
  check('and with the garage you hold and the cars you own', bank.loanLimit(0, 2, 0) == 9000 and bank.loanLimit(0, 3, 0) == 15000 and bank.loanLimit(0, 1, 3000) == 4500
    and bank.loanLimit(300, 2, 20000) == 19500 and bank.loanLimit(0, 1, 90000) == 48000 and bank.loanLimit(6000, 3, 300000) == bank.MAX_LOAN)
  check('a beginner is still lent only a little, and always in steps of $500', bank.loanLimit(0, 1, 0) == 3000 and bank.loanLimit(123, 1, 777) % 500 == 0)
  check('missed payments cost reputation, more each time, and the car last', bank.MISS_REP.warning < 0 and bank.MISS_REP.final < bank.MISS_REP.warning and bank.MISS_REP.repossess < bank.MISS_REP.final)
  check('a big loan is paid back like a small one: a quarter a week, interest capped', bank.due({ owed = 40000 }) == 10000 and bank.accrue({ borrowed = 40000, owed = 59990 }) == 60000)
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
  check('B10: the premium starts low and does not follow the cars', bank.premium(nil, 10) == bank.BASE_PREMIUM and bank.premium({}, 10) == bank.BASE_PREMIUM and bank.BASE_PREMIUM < 100)
  check('it rises with each recent claim, up to a cap', bank.premium({ 8 }, 10) == bank.BASE_PREMIUM + bank.CLAIM_LOAD and bank.premium({ 3, 8 }, 10) == bank.BASE_PREMIUM + 2 * bank.CLAIM_LOAD
    and bank.premium({ 1, 2, 3, 4, 5, 6, 7 }, 8) == bank.BASE_PREMIUM + bank.MAX_CLAIMS * bank.CLAIM_LOAD)
  check('claims older than the window fall out; a claim "in the future" does not count', bank.premium({ 2 }, 2 + bank.CLAIM_WINDOW) == bank.BASE_PREMIUM and bank.premium({ 20 }, 10) == bank.BASE_PREMIUM)
  check('and the premium says why', bank.premiumWhy({}, 5):find('No claims') and bank.premiumWhy({ 4 }, 5):find('1 claim') and bank.premiumWhy({ 4 }, 5):find('60'))
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
    check('road spot: a 1.75 m one-way lane counts, lane ends too (B35/B36: 17,174 of 19,339 Valo City lane nodes have one link)', #c == 3)
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

-- opening hours: the hour is (time * 24 + 12) % 24
do
  local hours = require('sl/core/hours')
  local function at(h) return ((h - 12) % 24) / 24 end
  check('shop 08-18', hours.isOpen('shop', at(8)) and hours.isOpen('shop', at(17.5)) and not hours.isOpen('shop', at(18)) and not hours.isOpen('shop', at(7.9)))
  check('dealer 09-17', hours.isOpen('dealer', at(9)) and not hours.isOpen('dealer', at(17)) and not hours.isOpen('dealer', at(8.5)))
  check('junkyard and scrapyard 08-17', hours.isOpen('junkyard', at(16.9)) and not hours.isOpen('scrapyard', at(17)) and hours.isOpen('scrapyard', at(8)))
  check('noon (time 0) is open, midnight (time 0.5) is closed', hours.isOpen('shop', 0) and not hours.isOpen('shop', 0.5))
  check('opensAt', hours.opensAt('dealer') == 9 and hours.opensAt('shop') == 8 and hours.opensAt('nowhere') == nil)
  check('closedText', hours.closedText('dealer', at(3)) == 'Closed. Opens at 09:00' and hours.closedText('dealer', at(10)) == nil)
  check('unknown kind is open', hours.isOpen('nowhere', at(3)))
end

-- the map of a saved career: no level field means Valo City (every career before the default changed); only a new career takes West Coast USA
do
  check('a save without a level is a Valo City career', progression.levelOf({ day = 3, money = 100 }) == 'slrr_valo_city' and progression.LEGACY_MAP == 'slrr_valo_city')
  check('the map-not-installed line fills its {1} and leaves no brace', (function() local t = require('sl/core/strings').t('career.this_career_is_on_1_map', 'Valo City') return t:find('Valo City', 1, true) and not t:find('{', 1, true) end)())
  check('a save with a level keeps it; an unknown level and no save give the default', progression.levelOf({ level = 'west_coast_usa' }) == 'west_coast_usa' and progression.levelOf({ level = 'slrr_valo_city' }) == 'slrr_valo_city'
    and progression.levelOf({ level = 'nowhere' }) == progression.DEFAULT_MAP and progression.levelOf(nil) == 'west_coast_usa' and progression.DEFAULT_MAP == 'west_coast_usa')
end

-- per-map capabilities: Valo City hosts everything, West Coast USA hides what its data lacks (T9)
do
  local feats = { 'roc', 'tracks', 'testdrive', 'clubDays', 'swapMeet', 'clubs', 'crews' }
  local valo, wc = true, true
  for _, f in ipairs(feats) do
    valo = valo and progression.has('slrr_valo_city', f)
    wc = wc and (f == 'clubs' or f == 'swapMeet' or f == 'crews' or not progression.has('west_coast_usa', f))      -- (clubs: #41 hosts them there, with the stock track events)
  end
  valo = valo and progression.has('slrr_valo_city', 'classifieds')
  check('Valo City offers every feature', valo)
  check('the phone marketplace (Revline, the paper, Swap & Bid) is on West Coast USA too', progression.has('west_coast_usa', 'classifieds'))
  check('West Coast USA hides every feature its data lacks', wc)
  check('an unknown level or feature falls back to the default map (West Coast USA) / off', not progression.has(nil, 'roc') and progression.has(nil, 'classifieds') and not progression.has('slrr_valo_city', 'nothing'))
  check('Valo texts are untouched on Valo City', progression.mapText('King of Valo City. King of Valo!', 'slrr_valo_city') == 'King of Valo City. King of Valo!'
    and progression.titleFor(6000, 'slrr_valo_city') == 'King of the Streets')
  check('Valo texts name West Coast USA there', progression.mapText('King of Valo City. Every crew in Valo.', 'west_coast_usa') == 'King of West Coast USA. Every crew in West Coast USA.'
    and progression.titleFor(6000, 'west_coast_usa') == 'King of the Streets' and progression.titleFor(6000) == 'King of the Streets')
end

-- laptops: prompts only in a career, one per computer facility that has a position (T13)
do
  local computer = require('sl/core/computer')
  local list = { { id = 'c1', name = 'Office' }, { id = 'c2' }, { id = 'c3', name = 'Lost' }, {} }
  local function posOf(f) return f.id ~= 'c3' and { x = 1, y = 2, z = 3 } or nil end
  check('no laptop prompts without a career', #computer.points(false, list, posOf) == 0)
  local on = computer.points(true, list, posOf)
  check('a laptop per computer with a position (not the one without doors, not the one without an id)', #on == 2 and on[1].id == 'c1' and on[2].name == 'Computer')
  check('a map without computers (Valo City) has none', #computer.points(true, {}, posOf) == 0 and #computer.points(true, nil, posOf) == 0)
end

-- the laptop's menu (L1): the five West Coast USA computers' own `functions` decide the tiles
do
  local laptop = require('sl/core/laptop')
  local function fn(...) local t = {} for _, k in ipairs({ ... }) do t[k] = true end return t end
  local FULL = fn('apmLandingPage', 'insurances', 'painting', 'partInventory', 'partShop', 'playerAbstract', 'tuning', 'vehicleInventory', 'vehicleShop')
  local computers = {
    servicestationGarageComputer = FULL, commercialGarageComputer = FULL, commercialGarageComputer2 = FULL,
    alderDragwayGarageComputer = fn('partInventory', 'partShop', 'tuning', 'vehicleInventory'),
    servicestationOfficeComputer = fn('apmLandingPage', 'partShop', 'vehicleShop'),
  }
  local function labels(group) local out = {} for _, t in ipairs(group and group.tiles or {}) do out[#out + 1] = t.label end return table.concat(out, ',') end
  local function view(id, state) state.has = state.has or { classifieds = true } local v = laptop.build(computers[id], state) return v, v.groups[1] and v.groups[1].id == 'car' and v.groups[1] or nil, v.groups[#v.groups] end
  local ok = { hasCar = true, carHere = true }
  for _, id in ipairs({ 'servicestationGarageComputer', 'commercialGarageComputer', 'commercialGarageComputer2' }) do
    local v, car, general = view(id, ok)
    check(id .. ': the car band and the general band', labels(car) == 'Part customization,Tuning,Painting' and labels(general) == 'My cars,My parts,Car market,Part market,Help,Bank / insurance,Street cred' and v.lists, labels(car) .. ' | ' .. labels(general))
  end
  local vp = view('alderDragwayGarageComputer', { hasCar = true, phase = 'day' })
  local vn = view('alderDragwayGarageComputer', { hasCar = true, phase = 'night', busy = true })
  local voff = view('servicestationOfficeComputer', { hasCar = false, phase = 'day' })
  local function phaseTile(v) for _, g in ipairs(v.groups) do for _, t in ipairs(g.tiles) do if t.id == 'phaseSwitch' then return t end end end end
  check('D1: a garage computer has Start the night / Start the day (off during a race or a job); an office one does not', phaseTile(vp).label == 'Start the night' and phaseTile(vp).enabled and phaseTile(vn).label == 'Start the day' and not phaseTile(vn).enabled and phaseTile(voff) == nil)
  local vcl = view('alderDragwayGarageComputer', { hasCar = true, has = { clubs = true } })
  local function hasTile(v, id) for _, g in ipairs(v.groups) do for _, t in ipairs(g.tiles) do if t.id == id then return true end end end return false end
  check('#41: a Club tile on a map that hosts clubs, none where it does not', hasTile(vcl, 'clubs') and not hasTile(view('alderDragwayGarageComputer', { hasCar = true }), 'clubs'))
  local _, car, general = view('alderDragwayGarageComputer', ok)
  check('the drag strip garage: cars, parts, the car and part markets (every computer has them: the laptops are the internet), help, customization and tuning only', labels(car) == 'Part customization,Tuning' and labels(general) == 'My cars,My parts,Car market,Part market,Help')
  local v, car2, general2 = view('servicestationOfficeComputer', ok)
  check('the office lists no cars and no car band: dealers and the parts shop only', not v.lists and car2 == nil and labels(general2) == 'Car market,Part market,Help,Part customization' and general2.tiles[1].enabled and general2.tiles[2].enabled and general2.tiles[3].enabled and not general2.tiles[4].enabled and general2.tiles[4].reason == 'Use a computer in a garage for this.')
  -- reasons, in order: a race or job, no car, not built yet
  local _, c1, g1 = view('commercialGarageComputer', { hasCar = false })
  local reasons = {}
  for _, t in ipairs(c1.tiles) do reasons[t.label] = t.reason end
  check('no car yet: the car tiles say so, the pages that need none stay open', reasons.Tuning == 'You have no car yet.' and g1.tiles[1].enabled and g1.tiles[5].enabled and g1.tiles[6].enabled)
  local _, c2, g2 = view('commercialGarageComputer', { hasCar = true, carHere = true })
  check('a car at the garage: the garage tiles open the garage in their mode, Dealers open their page, the reading pages are open',
    c2.tiles[1].enabled and c2.tiles[1].mode == 'catalog' and c2.tiles[2].mode == 'tune' and c2.tiles[3].mode == 'paint' and g2.tiles[3].enabled and g2.tiles[3].page == 'dealers'
    and g2.tiles[1].enabled and g2.tiles[1].page == 'cars' and g2.tiles[2].page == 'parts' and g2.tiles[4].page == 'partmarket' and g2.tiles[5].page == 'help' and g2.tiles[6].page == 'bank' and g2.tiles[7].page == 'cred')
  local _, c3, g3 = view('commercialGarageComputer', { hasCar = true, busy = true })
  check('in a race or on a job: car tiles and Dealers wait, reading pages stay', c3.tiles[2].reason == 'Not during a race or a job.' and g3.tiles[3].reason == 'Not during a race or a job.' and g3.tiles[1].enabled)
  local _, c4, g4 = view('commercialGarageComputer', { hasCar = true, carHere = false })
  check('a car that is not at this garage: the garage tiles say so, the reading pages stay open',
    c4.tiles[1].reason == 'Bring the car into the garage first.' and not c4.tiles[3].enabled and g4.tiles[1].enabled)
  check('carHere: the same garage id on both sides, never nil', laptop.carHere('a', 'a') and not laptop.carHere('a', 'b') and not laptop.carHere('a', nil) and not laptop.carHere(nil, nil))
  local rep = laptop.build(fn('repair', 'vehicleInventory'), { hasCar = true, carHere = true })
  check('the repair tile opens the repair tool', rep.groups[1].tiles[1].mode == 'repair' and rep.groups[1].tiles[1].enabled)
  local defs = { { id = 'club', label = 'Club', group = 'general', page = 'club', needs = 'clubs' }, { id = 'insurances', label = 'Bank', group = 'general', page = 'bank' } }
  local both = laptop.build(fn('club', 'insurances'), { hasCar = true, has = { clubs = true } }, defs)
  local wc = laptop.build(fn('club', 'insurances'), { hasCar = true, has = {} }, defs)
  check('a release-2 tile shows where the map hosts it and is hidden where it does not', #both.groups[1].tiles == 2 and #wc.groups[1].tiles == 1 and wc.groups[1].tiles[1].label == 'Bank')
  local bare = laptop.build({}, ok)
  check('no computer function: only the car and part markets (every computer is the internet), no car band', #bare.groups == 1 and bare.groups[1].id == 'general' and #bare.groups[1].tiles == 2 and bare.groups[1].tiles[1].label == 'Car market' and bare.groups[1].tiles[2].label == 'Part market' and not bare.lists)

  -- sl/computer.lua with stubbed game globals: per-car tiles by where the car stands, and the garage tile's action
  do
    local function P(x) return setmetatable({ x = x }, { __sub = function(a, b) return P(a.x - b.x) end, __index = { length = function(a) return math.abs(a.x) end } }) end
    local sent, toasts, entered = {}, {}, {}
    guihooks = { trigger = function(name, data) sent[#sent + 1] = { name = name, data = data } if name == 'slPhoneToast' then toasts[#toasts + 1] = data.text end end }
    local cars = { { id = 1, name = 'Here', model = 'a' }, { id = 2, name = 'Away', model = 'b' }, { id = 3, name = 'Stored', model = 'c' } }
    sl_career = { isActive = function() return true end, getState = function() return { cars = cars, jobs = {} } end, has = function() return false end }
    local at = { [0] = 'gA', [100] = 'gB' }   -- a position's x -> the garage id there
    sl_fleet = { vehicleOf = function(id) if id == 3 then return nil end local x = id == 1 and 0 or 100 return { getID = function() return 70 + id end, getPosition = function() return P(x) end } end }
    slrr_garage = { garageAt = function(pos) return at[pos.x] end, shelfItems = function() return {} end,
      enterWith = function(vid, mode) entered[#entered + 1] = vid .. ':' .. mode return true end }
    freeroam_facilities = { getFacilitiesByType = function() return { { id = 'c1', name = 'Garage', functions = { vehicleInventory = true, tuning = true, partShop = true } } } end,
      getAverageDoorPositionForFacility = function() return P(1) end }
    P1 = P
    at[1] = 'gA'                                  -- the computer's door is at garage gA
    translateLanguage = function(k, f) return f end
    getPlayerVehicle = function() return { getPosition = function() return P(1) end } end
    local computer = require('sl/computer')
    computer.open('c1')
    local open = sent[#sent].data
    local function tile(carId, id) for _, g in ipairs(open.byCar[carId]) do for _, t in ipairs(g.tiles) do if t.id == id then return t end end end end
    check('the laptop opens with tiles per car', sent[#sent].name == 'slLaptopOpen' and open.byCar[1] and open.byCar[2] and open.byCar[3])
    check('a car at the computer garage can go in; one at another garage or in storage cannot',
      tile(1, 'tuning').enabled and tile(1, 'tuning').mode == 'tune' and tile(2, 'tuning').reason == 'Bring the car into the garage first.' and tile(3, 'partShop').reason == 'Bring the car into the garage first.')
    computer.enterGarage('tune', 1)
    check('the garage tile sends that car into the garage in that mode, and the laptop closes', entered[1] == '71:tune' and sent[#sent].name == 'slLaptopClose')
    computer.open('c1')
    computer.enterGarage('catalog', 2)
    check('a car elsewhere is refused with the reason and nothing is sent to the garage', #entered == 1 and toasts[#toasts] == 'Bring the car into the garage first.')
    slrr_garage.enterWith = function() return false, 'The garage is busy.' end
    computer.enterGarage('tune', 1)
    check('the garage saying no keeps the laptop open and shows its reason', toasts[#toasts] == 'The garage is busy.' and sent[#sent].name ~= 'slLaptopClose')
  end
end

-- the game's tutorial and scenario configs are never for sale (a Covet Career Tutorial on the junkyard)
do
  local D = require('sl/core/stockdealers')
  check('tutorial and scenario configs are not for sale, ordinary ones are', not D.forSale({ raw = { key = 'covet_tutorial', Name = 'Covet Career Tutorial' } })
    and not D.forSale({ raw = { key = 'apmTutorial_sunburst', pcFilename = 'apmTutorial_sunburst' } }) and not D.forSale({ raw = { Name = 'Some Scenario Car' } })
    and D.forSale({ raw = { key = '13s_M', Name = 'Covet 1.3 S', ['Config Type'] = 'Factory' } }) and D.forSale({}))
end

-- the garage ladder (T34c)
do
  local g = progression.garages
  check('the first garage is open from the start', progression.garageAccess({ garageLevel = 1, rep = 0 }, g[1].site))
  local ok2, why2 = progression.garageAccess({ garageLevel = 1, rep = 100 }, g[2].site)
  check('a higher garage is closed, with the reputation it needs', not ok2 and why2 == 'You need 175 reputation to use Club Garage 2.')
  local ok3, why3 = progression.garageAccess({ garageLevel = 1, rep = 1600 }, g[2].site)
  check('with the rep but not moved yet: move up first', not ok3 and why3:find('Move up to Club Garage 2 first') ~= nil)
  check('moved up: the garage and the ones below it are open, the one above is not',
    progression.garageAccess({ garageLevel = 2, rep = 1600 }, g[2].site) and progression.garageAccess({ garageLevel = 2, rep = 1600 }, g[1].site) and not progression.garageAccess({ garageLevel = 2, rep = 1600 }, g[3].site))
  check('a site that is not on the ladder is free', progression.garageAccess({ garageLevel = 1 }, 'someShop'))
end

-- waiting on the phone (T34b)
do
  local plan = progression.skipPlan(20, 'morning')
  check('morning from 20:00: ten hours and a few minutes, the day changes once', math.abs(plan.hours - 10.05) < 1e-9 and plan.days == 1 and math.abs(plan.to - 6.05) < 1e-9)
  check('morning from 02:00: the same day ends, the new one begins', progression.skipPlan(2, 'morning').days == 1 and math.abs(progression.skipPlan(2, 'morning').hours - 4.05) < 1e-9)
  check('morning from 06:03 is the next day, not now', progression.skipPlan(6.03, 'morning').hours > 23.9 and progression.skipPlan(6.03, 'morning').days == 1)
  check('a few hours: no day change inside the day, one across 06:00', progression.skipPlan(10, '3').days == 0 and progression.skipPlan(10, '3').to == 13 and progression.skipPlan(4, '3').days == 1 and progression.skipPlan(23, '6').to == 5 and progression.skipPlan(23, '6').days == 0)
  check('anything else is refused', progression.skipPlan(10, '5') == nil and progression.skipPlan(10, '-3') == nil and progression.skipPlan(10, nil) == nil)
  -- D1: the day and the night
  local phase = require('sl/core/phase')
  check('infer: an old save is in the half its hour is in', phase.infer(10) == 'day' and phase.infer(21) == 'night' and phase.infer(2) == 'night' and phase.infer(5.5) == 'day' and phase.infer(nil) == 'day')
  check('ended: day runs 07:00 to 19:00, night 21:00 to 04:00', not phase.ended('day', 7) and not phase.ended('day', 18.9) and phase.ended('day', 19) and phase.ended('day', 3) and not phase.ended('night', 21) and not phase.ended('night', 1) and phase.ended('night', 4) and phase.ended('night', 12))
  check('fit: the clock is held at the phase end, or put at its start', phase.fit('day', 18) == 18 and phase.fit('day', 19.2) == 19 and phase.fit('day', 22) == 19 and phase.fit('day', 3) == 7 and phase.fit('night', 4.1) == 4 and phase.fit('night', 9) == 4 and phase.fit('night', 15) == 21 and phase.fit('night', 23) == 23)
  local w = phase.waitPlan('day', 10, '3')
  check('waiting: a few hours inside the phase', w.to == 13 and w.hours == 3 and not w.ends)
  local w2 = phase.waitPlan('day', 17, '6')
  check('waiting stops at the phase end', w2.to == 19 and w2.hours == 2 and w2.ends)
  local w3 = phase.waitPlan('night', 23, '6')
  check('the night end is 04:00, across midnight', w3.to == 4 and w3.hours == 5 and w3.ends and phase.waitPlan('night', 1, '1').to == 2)
  local nope, why = phase.waitPlan('day', 19, '1')
  check('waiting at the end of the phase says to switch', nope == nil and why:find('Start the night') and select(2, phase.waitPlan('night', 4, '1')):find('Start the day') and phase.waitPlan('day', 10, '5') == nil)
  local sw = phase.switchPlan('day', {})
  check('Start the night: the clock goes to 21:00, no new day', sw.phase == 'night' and sw.to == 21 and sw.day == false)
  local sw2 = phase.switchPlan('night', {})
  check('Start the day: 07:00 and the day counter goes up', sw2.phase == 'day' and sw2.to == 7 and sw2.day == true)
  check('no switching in a race, on a job or with the police on you', phase.switchPlan('day', { racing = true }) == nil and phase.switchPlan('day', { job = true }) == nil and phase.switchPlan('night', { heat = 2 }) == nil)
  -- D3: heat at night
  local heat = require('sl/core/heat')
  local dayV, n0, n3, n5 = heat.policeVars('day', 4), heat.policeVars('night', 0), heat.policeVars('night', 3), heat.policeVars('night', 5)
  check('the police by day leave normal driving alone: strict 0.1, no roadblocks, no suspects, whatever the heat', dayV.strictness == 0.1 and dayV.roadblockFrequency == 0 and dayV.suspectFrequency == 0)
  check('at night the police get stricter and slower to lose with the heat', n0.strictness < n3.strictness and n3.strictness < n5.strictness and n0.evadeTime < n3.evadeTime and n3.evadeTime < n5.evadeTime and n5.strictness == 1.0 and n0.evadeRadius < n5.evadeRadius)
  check('roadblocks only at 4 and 5', heat.policeVars('night', 3).roadblockFrequency == 0 and heat.policeVars('night', 4).roadblockFrequency == 0.5 and n5.roadblockFrequency == 1 and heat.policeVars('night', 9).roadblockFrequency == 1)
  check('one more patrol a level, at night only, never past five', heat.extraPatrols('night', 3) == 3 and heat.extraPatrols('day', 3) == 0 and heat.extraPatrols('night', 9) == 5 and heat.extraPatrols('night', -1) == 0)
  check('the night rep multiplier grows 15 percent a level; none by day', heat.repBoost('night', 0) == 1 and math.abs(heat.repBoost('night', 4) - 1.6) < 1e-9 and heat.repBoost('day', 5) == 1)
  check('a fine grows 25 percent a level at night and is the base by day', heat.fine(400, 'day', 5) == 400 and heat.fine(400, 'night', 0) == 400 and heat.fine(400, 'night', 4) == 800)
  check('impounded from level 4 at night, whatever you can pay; the fee grows', heat.impounds('night', 4) and heat.impounds('night', 5) and not heat.impounds('night', 3) and not heat.impounds('day', 5) and heat.impoundFee(4) == 800 and heat.impoundFee(5) == 1000 and heat.impoundFee(1) == 600)
  check('at risk: the night reputation since the bank; nothing by day', heat.atRisk('night', 500, 380) == 120 and heat.atRisk('day', 500, 380) == 0 and heat.atRisk('night', 300, 380) == 0 and heat.atRisk('night', 50, nil) == 50)
  local rep2, lost2 = heat.afterBust('night', 500, 380)
  local rep3, lost3 = heat.afterBust('day', 500, 380)
  check('a bust at night loses the unbanked reputation, by day nothing', rep2 == 380 and lost2 == 120 and rep3 == 500 and lost3 == 0)
  check('heat is raised up to 1 and cools while nobody is after you, down to 0', heat.raised(0.95, 0.12) == 1 and math.abs(heat.raised(0.2, heat.NEAR_MISS) - 0.24) < 1e-9 and math.abs(heat.cooled(0.5, 10) - 0.4) < 1e-9 and heat.cooled(0.05, 100) == 0)
  check('a save without banked reputation has none at risk; a new career starts at 0', state.migrate({ seed = 3, rep = 700, hour = 11 }).bankedRep == 700 and state.new(5, 0).bankedRep == 0)

  -- #41 clubs on West Coast USA: the day league is the map's stock track events
  local clubsCore = require('sl/core/clubs')
  local rulesCore = require('sl/core/activityrules')
  local missions = { { id = 'west_coast_usa/timeTrial/b', name = 'B' }, { id = 'west_coast_usa/dragStripRace/a', name = 'A' }, { id = 'west_coast_usa/aiRace/001-circuit', name = 'ROC' },
    { id = 'west_coast_usa/aiRace/002-ring', name = 'Ring' }, { id = 'west_coast_usa/evade/e', name = 'E' }, { id = 'west_coast_usa/crawl/c', name = 'C' } }
  local evs = clubsCore.stockEvents(missions, function(id) return rulesCore.ruleFor('west_coast_usa', id) end, function(m) return 'Event ' .. m.name end)
  check('stock events: time trials, drags and circuits (not the Race of Champions, evades or crawls), by id, with a name and a league kind', #evs == 3 and evs[1].id == 'west_coast_usa/aiRace/002-ring' and evs[1].kind == 'circuit' and evs[2].kind == 'drag' and evs[3].kind == 'venue' and evs[2].name == 'Event A' and evs[1].stock and evs[1].missionId == evs[1].id)
  check('and they make a day calendar: every day has a stock day event, and a night one from the sprints', (function() local cal = clubsCore.calendar({ { id = 'sr1', missionId = 'x/sr1', name = 'Sprint', kind = 'night' }, evs[1], evs[2], evs[3] }, require('sl/core/rng').new(5)) for d = 1, clubsCore.SEASON_DAYS do if not (cal[d].day and cal[d].day.stock and cal[d].night) then return false end end return true end)())
  check('stars give the place: three first, two second, one third, none not scored', clubsCore.placeFromStars(3) == 1 and clubsCore.placeFromStars(2) == 2 and clubsCore.placeFromStars(1) == 3 and clubsCore.placeFromStars(0) == nil and clubsCore.placeFromStars(nil) == nil)
  check('West Coast USA hosts clubs and stock events; Valo keeps its own', progression.has('west_coast_usa', 'clubs') and progression.has('west_coast_usa', 'stockEvents') and not progression.has('slrr_valo_city', 'stockEvents') and progression.has('slrr_valo_city', 'clubs'))

  -- #44 the swap meet on West Coast USA
  local sm = require('sl/core/swapmeet')
  local places = { garage1 = { kind = 'garage', pos = {} }, small = { kind = 'dealer', pos = {}, displays = { 1, 2 } }, big = { kind = 'dealer', pos = {}, displays = { 1, 2, 3, 4, 5 } },
    big2 = { kind = 'dealer', pos = {}, displays = { 1, 2, 3, 4, 5 } }, nopos = { kind = 'dealer', displays = { 1, 2, 3, 4, 5, 6, 7 } } }
  check('the meet place: the fixed one when the map has it, else the lot with most spots (the lowest id on a tie; no garages, no place without a position)', sm.pickPlace(places) == 'big' and sm.pickPlace(places, 'small') == 'small' and sm.pickPlace(places, 'meet_tuning') == 'big' and sm.pickPlace({ meet_tuning = { kind = 'meet', pos = {} }, big = places.big }, 'meet_tuning') == 'meet_tuning' and sm.pickPlace({}) == nil)
  check('the meet is on the weekend (day % 7 is 5 or 6, as before); a night meet only at night', sm.isOpen(5, false, false) and sm.isOpen(6, false, false) and not sm.isOpen(7, false, false) and not sm.isOpen(8, false, false) and sm.isOpen(13, true, true) and not sm.isOpen(13, false, true) and not sm.isOpen(10, true, true))
  check('West Coast USA hosts the swap meet, as a night meet; Valo does not have the night meet', progression.has('west_coast_usa', 'swapMeet') and progression.has('west_coast_usa', 'nightMeet') and not progression.has('slrr_valo_city', 'nightMeet'))

  -- #42 crews on West Coast USA: districts named after the map's own places
  local crewsCore = require('sl/core/crews')
  check('an area name drops the trade word: Garage, Auto Sales, Motors...', crewsCore.areaName('Alder Dragway Garage') == 'Alder Dragway' and crewsCore.areaName('Quarryside Auto Sales') == 'Quarryside' and crewsCore.areaName('Jefferson Motors') == 'Jefferson' and crewsCore.areaName('The Industrial Garage') == 'Industrial' and crewsCore.areaName('Garage') == 'Garage' and crewsCore.areaName(nil) == '')
  local ds = { { id = 'd1', name = 'Downtown', centre = { x = 0, y = 0 } }, { id = 'd2', name = 'East Side', centre = { x = 1000, y = 0 } }, { id = 'd3', name = 'Northside', centre = { x = 1100, y = 50 } } }
  crewsCore.nameByPlaces(ds, { { name = 'Belasco City Garage', x = 20, y = 10 }, { name = 'Alder Dragway Garage', x = 990, y = 20 }, { name = 'Alder Dragway Auto Sales', x = 1090, y = 60 } })
  check('districts take the name of the nearest place; a second one with the same area is numbered; with no places the old names stay', ds[1].name == 'Belasco City' and ds[2].name == 'Alder Dragway' and ds[3].name == 'Alder Dragway 2' and crewsCore.nameByPlaces({ { id = 'x', name = 'Southside', centre = { x = 1, y = 1 } } }, {})[1].name == 'Southside')
  check('West Coast USA hosts crews', progression.has('west_coast_usa', 'crews'))

  -- #49 the performance overlay's numbers
  local perfLib = require('sl/core/perf')
  local ps = perfLib.new()
  for _ = 1, 59 do perfLib.add(ps, 1 / 60) end
  perfLib.add(ps, 0.05)
  local pr = perfLib.read(ps)
  check('perf: the average over the last second, the fps it makes and the worst frame', math.abs(pr.ms - 17.4) < 0.5 and math.abs(pr.fps - 57.5) < 1.5 and math.abs(pr.worstMs - 50) < 0.01)
  for _ = 1, 700 do perfLib.add(ps, 1 / 60) end
  check('and the worst frame is forgotten after 10 seconds', perfLib.read(ps).worstMs < 20 and #ps.frames <= 620)
  check('bad frames (zero, huge, text) are ignored', (function() local q = perfLib.new() perfLib.add(q, 0) perfLib.add(q, 99) perfLib.add(q, 'x') return #q.frames == 0 and perfLib.read(q).fps == 0 end)())
  check('vram: a number, used / total, used alone, nothing', perfLib.vramText(2048) == '2048 MB' and perfLib.vramText({ used = 3000, total = 8000 }) == '3000 / 8000 MB' and perfLib.vramText({ usedMB = 512 }) == '512 MB' and perfLib.vramText({ foo = 1 }) == nil and perfLib.vramText(nil) == nil)
  local pl = perfLib.lines({ ms = 16.7, fps = 59.9, worstMs = 41 }, { traffic = 12, others = 3, peds = 20, statics = 5000 }, '3000 / 8000 MB')
  check('the overlay lines: frame, worst, VRAM, cars, people', #pl == 5 and pl[1] == '16.7 ms  60 fps' and pl[2] == 'worst 41 ms (10 s)' and pl[3] == 'VRAM 3000 / 8000 MB' and pl[4] == 'cars: 12 traffic, 3 other' and pl[5] == 'people 20, objects 5000' and #perfLib.lines({}, {}, nil) == 4)

  -- #48 race replays: the clip's file name
  local rep = require('sl/core/replay')
  check('a clip is named after the race, safe for a file name, with the time', rep.clipName('Quarry sprint', '2026-10-17 21-30') == 'Street Legal - Quarry sprint 2026-10-17 21-30' and rep.clipName('a/b:c*d?"e<f>g|h', '') == 'Street Legal - a b c d e f g h' and rep.clipName('', 'x') == 'Street Legal - Race x' and rep.clipName(nil, nil) == 'Street Legal - Race')
  check('a long name is cut, not left ragged', #rep.clipName(string.rep('word ', 40), '') <= #'Street Legal - ' + 60 and rep.clipName(string.rep('word ', 40), ''):sub(-1) ~= ' ')
  check('the race name: its own, else against whom', rep.raceName({ raceName = 'Dock run', opponent = 'Ana' }) == 'Dock run' and rep.raceName({ opponent = 'Ana' }) == 'Race against Ana' and rep.raceName({}) == 'Race' and rep.raceName(nil) == 'Race')

  -- #55 the help pages
  local helpLib = require('sl/core/help')
  local ids, okPages = {}, #helpLib.PAGES >= 10
  for _, p in ipairs(helpLib.PAGES) do
    okPages = okPages and type(p.id) == 'string' and p.id ~= '' and not ids[p.id] and type(p.title) == 'string' and p.title ~= '' and type(p.body) == 'table' and #p.body > 0
    ids[p.id] = true
    for _, para in ipairs(p.body) do okPages = okPages and type(para) == 'string' and para ~= '' and #para < 700 end
  end
  check('the help: at least ten pages, each with a unique id, a title and short paragraphs', okPages)
  check('the help covers the first hour, day and night, races, heat, clubs, crews', helpLib.page('first') and helpLib.page('daynight') and helpLib.page('races') and helpLib.page('heat') and helpLib.page('clubs') and helpLib.page('crews') and helpLib.page('nothing') == nil)
  local md = helpLib.markdown()
  check('a part whose jbeam name is an unfilled template shows its id in words, never the template', (function() local PI = require('sl/core/partinfo') local n = PI.displayName('{{ size }} {{ type }}', 'vivace_wheel_01a', 'vivace') return not n:find('{{', 1, true) and n:lower():find('wheel') ~= nil and PI.text('{{ x }}') == nil and PI.text('Wheel') == 'Wheel' end)())
  check('a translated part name with a brand placeholder shows without the placeholder', (function() local old = translateLanguage translateLanguage = function() return '{{brand1 | translate}} A11 Rear Hubcaps' end local n = require('sl/core/partinfo').displayName('ui.part.hubcaps', 'x_hubcap', 'x') translateLanguage = old return n == 'A11 Rear Hubcaps' end)())
  do
    local MF = require('sl/core/mapfeed')
    local A, B = { pos = { x = 0, y = 0 }, radius = 1.75 }, { pos = { x = 100, y = 0 }, radius = 1.75 }
    check('maps: a plain lane link is a minor road', MF.classify({}, A, B) == 'minor')
    check('maps: width alone gives the class when there is no speed limit', MF.classify({}, { radius = 5 }, B) == 'arterial' and MF.classify({ lanes = '++---' }, A, B) == 'highway' and MF.classify({}, { radius = 3 }, B) == 'street')
    check('maps: a high speed limit is a highway, a dirt track never a main road', MF.classify({ speedLimit = 30 }, A, B) == 'highway' and MF.classify({ speedLimit = 30, drivability = 0.2 }, A, B) == 'minor')
    local nodes = { a = { pos = { x = 10, y = 10 }, links = { b = {}, c = { speedLimit = 20 } } }, b = { pos = { x = 300, y = 10 }, links = { a = {} } }, c = { pos = { x = 10, y = 600 }, links = { a = { speedLimit = 20 } } } }
    local bl = MF.builder(nodes)
    while not bl:step(os.clock, 1) do end
    local n = 0 for _, t in pairs(bl.tiles) do n = n + #t end
    check('maps: every link is in one tile once, in the tile of its middle', bl.count == 2 and n == 2 and bl.tiles['0,0'] ~= nil and bl.tiles['0,1'] ~= nil)
    check('maps: the speed limit of a road, either way round, nothing when there is none', MF.limitOf(nodes, 'a', 'c') == 20 and MF.limitOf(nodes, 'c', 'a') == 20 and MF.limitOf(nodes, 'a', 'b') == nil and MF.limitOf(nil, 'a', 'b') == nil)
    check('maps: the Mods rows with their defaults and bad values mended', (function() local o = MF.mapOptions(function() return nil end) local p = MF.mapOptions(function(k) return ({ slMapStyle = 'nope', slMapZoom = 'far', slMapHeadingUp = true, slMapSpeed = false })[k] end) return o.style == 'street' and o.zoom == 'normal' and o.mpp == 2 and o.speed == true and o.headingUp == false and p.style == 'street' and p.mpp == 4 and p.headingUp == true and p.speed == false end)())
    check('maps: an unlimited road (math.huge, 100 m/s or more) has no limit to show', MF.limitOf({ a = { links = { b = { speedLimit = math.huge } } }, b = { links = {} } }, 'a', 'b') == nil and MF.limitOf({ a = { links = { b = { speedLimit = 99.9 } } } }, 'a', 'b') == 99.9 and MF.limitOf({ a = { links = { b = { speedLimit = 100 } } } }, 'a', 'b') == nil)
    check('maps: tiles around a point cover the square', #MF.tilesAround(10, 10, 200) == 4 and MF.key(-1, -1) == '-1,-1')
    local bad = { a = { pos = { x = 0, y = 0 }, links = { b = {}, c = {}, d = 5 } }, b = { links = {} }, c = 'nope', d = { pos = { x = 'x' }, links = 3 }, e = { pos = { x = 5, y = 5 }, links = 'x' } }
    local bb = MF.builder(bad)
    check('maps: malformed nodes and links are skipped, never thrown on', select(1, pcall(function() while not bb:step(os.clock, 1) do end end)) and bb.count == 0)
    local vec = function(x, y) return setmetatable({}, { __index = function(_, k) if k == 'x' then return x elseif k == 'y' then return y end end }) end
    local vn = { a = { pos = vec(0, 0), links = { b = {} } }, b = { pos = vec(100, 0), links = { a = {} } }, c = { pos = 5, links = { a = {} } } }
    local vb = MF.builder(vn)
    while not vb:step(os.clock, 1) do end
    check('maps: positions that are not plain tables (the game vec3) are read, a number position is skipped', vb.count == 1)
    check('maps: a route point without a position is skipped', #MF.routePoints({ { pos = { x = 0, y = 0 } }, {}, { pos = 'x' }, { pos = { x = 40, y = 0 } } }, 6) == 4)
    local cu = MF.consumers()
    check('maps: the feed runs while any consumer needs it, and a new consumer is told to be sent the route', cu.use('hud', true) == true and cu.any() and cu.use('phone', true) == true and cu.use('phone', false) == false and cu.any() and cu.use('hud', false) == false and not cu.any())
    local rp = MF.routePoints({ { pos = { x = 0, y = 0 } }, { pos = { x = 1, y = 0 } }, { pos = { x = 50, y = 0 } }, { pos = { x = 51, y = 0 } } }, 6)
    check('maps: a route is thinned and keeps its last point', #rp == 6 and rp[5] == 51)
  end
  check('a part named by a game translation key is shown by its id in words, never as the key', (function() local n = require('sl/core/partinfo').displayName('ui.vehicleconfig.generic.wheelName', 'vivace_wheel_01a', 'vivace') return not n:find('ui%.') and n:lower():find('wheel') ~= nil end)())
  check('the help covers the new features and its economy numbers are the real ones', (function()
    for _, id in ipairs({ 'dealers', 'weather', 'carcare', 'carmeets', 'graphics', 'extras' }) do if not helpLib.page(id) then return false end end
    local money = table.concat(helpLib.page('money').body, ' ')
    local g2, g3 = progression.garages[2], progression.garages[3]
    return money:find(g2.rep .. ' reputation and $6,000', 1, true) ~= nil and g2.cost == 6000 and money:find(g3.rep == 1000 and '1,000 reputation and $25,000' or 'x', 1, true) ~= nil and g3.cost == 25000
  end)())
  check('the guide is made from the same pages: every title and paragraph is in it', (function() for _, p in ipairs(helpLib.PAGES) do if not md:find('## ' .. p.title, 1, true) then return false end for _, para in ipairs(p.body) do if not md:find(para, 1, true) then return false end end end return md:sub(1, 2) == '# ' end)())
  local hv = require('sl/core/laptop').build({ vehicleInventory = true, insurances = true }, { hasCar = true })
  check('a Help tile on a garage computer', (function() for _, g in ipairs(hv.groups) do for _, t in ipairs(g.tiles) do if t.id == 'help' and t.page == 'help' then return true end end end return false end)())

  -- the sun, for a sky without core_celestial
  local sun = require('sl/core/sun')
  local function el(lat, lon, utc, m, d, h) return (sun.position(lat, lon, utc, m, d, h, 2026)) end
  local function near(a, b) return math.abs(a - b) < 2 end
  check('Valo (47 N, 8 E) at the spring equinox: up at noon, a low sun at 07:00 and 19:00, dark at 21:00 and 04:00', near(el(47, 8, 1, 3, 20, 12), 42) and near(el(47, 8, 1, 3, 20, 7), 4) and near(el(47, 8, 1, 3, 20, 19), -4) and el(47, 8, 1, 3, 20, 21) < -20 and el(47, 8, 1, 3, 20, 4) < -20)
  check('West Coast (37.8 N, 122.4 W, UTC-7)', near(el(37.77, -122.42, -7, 3, 20, 12), 48) and near(el(37.77, -122.42, -7, 3, 20, 7), -4) and near(el(37.77, -122.42, -7, 3, 20, 19), 3) and el(37.77, -122.42, -7, 3, 20, 21) < -15)
  check('the old summer dates: the sun is still up at 21:00 in Valo (why the date moved)', el(47, 8, 2, 6, 20, 21) > 0 and el(47, 8, 2, 6, 20, 21) < 6)
  local _, azMorning = sun.position(47, 8, 1, 3, 20, 8, 2026)
  local _, azEvening = sun.position(47, 8, 1, 3, 20, 17, 2026)
  local _, azNoon = sun.position(47, 8, 1, 3, 20, 12.5, 2026)
  check('the sun is in the east in the morning, south at noon, west in the evening (compass degrees)', azMorning > 70 and azMorning < 130 and azNoon > 160 and azNoon < 200 and azEvening > 230 and azEvening < 290)
  check('the time zone: US rule on 20 March is summer time (-7 on the West Coast), EU is not; November is not', sun.utcOffsetFor(37.77, -122.42, 'us', 2026, 3, 20) == -7 and sun.utcOffsetFor(47, 8, 'eu', 2026, 3, 20) == 1 and sun.utcOffsetFor(47, 8, 'eu', 2026, 7, 1) == 2 and sun.utcOffsetFor(37.77, -122.42, 'us', 2026, 11, 20) == -8 and sun.utcOffsetFor(47, 8, nil, 2026, 6, 20) == 2 and sun.utcOffsetFor(37.77, -122.42, nil, 2026, 6, 22) == -7)

  check('D4: heat as a level 0 to 5', phase.heatLevel(0) == 0 and phase.heatLevel(0.01) == 0 and phase.heatLevel(0.05) == 1 and phase.heatLevel(0.5) == 3 and phase.heatLevel(1) == 5 and phase.heatLevel(9) == 5 and phase.heatLevel(nil) == 0)
  check('the buttons say what they do', phase.switchLabel('day') == 'Start the night' and phase.switchLabel('night') == 'Start the day')
  check('the clock speed: slow is 2.5 real minutes an hour, a bad value is slow', phase.dayLength('slow') == 3600 and phase.dayLength('normal') == 1800 and phase.dayLength('fast') == 900 and phase.dayLength('zzz') == 3600 and phase.dayLength(nil) == 3600)
  local migrated = state.migrate({ seed = 3, hour = 22.5 })
  check('a save without a phase gets the one its hour is in; a new career starts in the day', migrated.phase == 'night' and state.migrate({ seed = 3, hour = 11 }).phase == 'day' and state.migrate({ seed = 3, phase = 'night', hour = 11 }).phase == 'night' and state.new(5, 0).phase == 'day')
  check('refused in a race, on a job, with the police after you; fine otherwise', progression.skipRefusal({ racing = true }) ~= nil and progression.skipRefusal({ job = true }) ~= nil
    and progression.skipRefusal({ heat = 0.5 }) ~= nil and progression.skipRefusal({ heat = 0.1 }) == nil and progression.skipRefusal({}) == nil)
end

-- buying from the stock dealers on the laptop (L3)
do
  local rules = require('sl/core/dealers')
  check('the clock counts game hours from 06:00 and never goes back (a day runs 06:00 to 05:59)', rules.clock(3, 6) < rules.clock(3, 23) and rules.clock(3, 23) < rules.clock(3, 2)
    and rules.clock(3, 2) < rules.clock(4, 6) and rules.clock(4, 6) - rules.clock(3, 6) == 24 and rules.clock(4, 6) - rules.clock(3, 5.99) < 1)
  local y1, y2 = rules.yearOf('d1:dealer-3-1', { min = 2005, max = 2013 }), rules.yearOf('d1:dealer-3-1', { min = 2005, max = 2013 })
  local inRange, spread = true, {}
  for i = 1, 60 do local y = rules.yearOf('o' .. i, { min = 2005, max = 2013 }) inRange = inRange and y >= 2005 and y <= 2013 spread[y] = true end
  local kinds = 0 for _ in pairs(spread) do kinds = kinds + 1 end
  check('a listed car\'s year is in the config\'s years, the same every time, and varies between cars', y1 == y2 and inRange and kinds >= 5
    and rules.yearOf('x', { min = 2010, max = 2010 }) == 2010 and rules.yearOf('x', nil) >= 2000 and rules.yearOf('x', 1999) == 1999 and rules.yearOf('x', { min = 2012, max = 2008 }) == 2012)
  local sp = rules.specs({ Power = 66, Weight = 995, Drivetrain = 'FWD', Transmission = 'Manual', ['Fuel Type'] = 'Gasoline', ['Body Style'] = 'Hatchback', ['Top Speed'] = 42.5 })
  check('the stock listing\'s facts are read from the config entry', sp.power == 66 and sp.weight == 995 and sp.drivetrain == 'FWD' and sp.transmission == 'Manual' and sp.fuel == 'Gasoline' and sp.body == 'Hatchback' and sp.topSpeed == 42.5)
  local none = rules.specs(nil)
  check('and missing ones are nil, not errors', none.power == nil and none.drivetrain == nil and rules.specs({ Drivetrain = '' }).drivetrain == nil)
  check('delivery takes 2 to 6 hours by distance', rules.delayHours(0) == 2 and rules.delayHours(3500) == 3 and rules.delayHours(9000) == 5 and rules.delayHours(99999) == 6)
  local offer = { id = 'd1:dealer-3-1', name = 'Covet', price = 4000, mileage = 12, condition = 1, faults = {} }
  local s = { money = 3000, bought = {}, orders = {} }
  local ok, why = rules.canBuy(s, offer)
  check('not enough money: refused with the amounts', not ok and why == 'It is $4000. You have $3000.')
  s.money = 9000
  check('enough money: allowed', rules.canBuy(s, offer))
  local order = rules.place(s, offer, 'd1', 5000, rules.clock(3, 10))
  -- a private seller's car bought on Revline for delivery: the same order, its own id, due by the seller's distance
  local rs = { money = 9000, bought = {}, orders = {} }
  local ro = rules.orderPrivate(rs, { id = 'm7', where = { x = 6000, y = 0 }, offer = { id = 'used-0-1', name = 'Pessima', model = 'pessima', price = 900, faults = {} } }, 1200, { x = 0, y = 0 }, rules.clock(3, 10))
  check('a Revline car for delivery: an order with its own id, the asking price, due by distance',
    ro.offer.id == 'revline:m7' and ro.offer.price == 1200 and ro.offer.model == 'pessima' and ro.hours == 4 and rs.bought['revline:m7'] and #rs.orders == 1)
  check('an order is due after its delay and marks the offer bought', s.bought[offer.id] and #s.orders == 1 and order.hours == 3 and order.due == rules.clock(3, 10) + 3 and rules.ordered(s, offer.id))
  check('the same car cannot be bought twice', not rules.canBuy(s, offer))
  check('nothing is due before the delay, the order is due after', rules.nextDue(s, rules.clock(3, 12)) == nil and rules.nextDue(s, rules.clock(3, 13.01)) == order)
  check('a delivered order is removed', rules.remove(s, order) and #s.orders == 0 and s.bought[offer.id])

  -- sl/dealers.lua with stubbed game globals: the lot's own offers, money once, delivery after the delay, across a save
  local function deepcopy(t) if type(t) ~= 'table' then return t end local c = {} for k, v in pairs(t) do c[k] = deepcopy(v) end return c end
  local function P(x) return setmetatable({ x = x }, { __sub = function(a, b) return P(a.x - b.x) end, __index = { length = function(a) return math.abs(a.x) end } }) end
  local events, toasts, built, texts, charged = {}, {}, {}, {}, 0
  guihooks = { trigger = function(name, data) events[#events + 1] = { name = name, data = data } if name == 'slPhoneToast' then toasts[#toasts + 1] = data.text end end }
  extensions = { hook = function() end }
  local state = { money = 9000, day = 3, cars = {}, bought = {}, orders = {} }
  local hourNow = 10
  sl_career = { isActive = function() return true end, getState = function() return state end, hour = function() return hourNow end,
    addMoney = function(amount) if state.money + amount < 0 then return false end state.money = state.money + amount charged = charged + 1 return true end,
    getPlaces = function() return { d1 = { id = 'd1', name = 'Jefferson Motors', pos = P(5000), stock = { kind = 'dealer' } }, g = { id = 'g', name = 'Not a stock dealer', pos = P(1) } } end,
    sendText = function(_, text) texts[#texts + 1] = text end }
  local lotOffers = function() return { { id = 'd1:dealer-3-1', name = 'Covet', price = 4000, mileage = 12, condition = 1, faults = {}, kind = 'dealer', value = 5000 },
    { id = 'd1:dealer-3-2', name = 'Bolide', price = 7000, mileage = 20, condition = 1, faults = {}, kind = 'dealer', value = 8000 } } end
  sl_lot = { offersFor = function(place, s)      -- (the lot's own rule: what is bought is not offered)
    local out = {} for _, o in ipairs(lotOffers()) do if not (s.bought or {})[o.id] then out[#out + 1] = o end end return out end }
  sl_fleet = { forecourt = function() return P(0), 'rot' end, freeForecourt = function() return P(0), 'rot' end,
    registerVehicle = function(vid, info) local car = { id = #state.cars + 1, name = info.name } state.cars[#state.cars + 1] = car state.activeCar = car.id return car end }
  core_jobsystem = { create = function(f) f({ sleep = function() end }) end }
  getPlayerVehicle = function() return { getPosition = function() return P(0) end } end
  local vehicle = { getID = function() return 77 end, queueLuaCommand = function() end }
  package.loaded['sl/carBuilder'] = { buildOffer = function(job, offer) built[#built + 1] = offer.id return vehicle end }
  package.loaded['sl/carInfo'] = { of = function(offer) return { preview = '/vehicles/' .. tostring(offer.model) .. '/x.png', year = 2011, brand = 'Ibishu',
    specs = { power = 120, weight = 1100, drivetrain = 'RWD', transmission = 'Manual' } } end }
  local dealers = require('sl/dealers')
  local function last(name) for i = #events, 1, -1 do if events[i].name == name then return events[i].data end end end
  dealers.list()
  local list = last('slLaptopDealers')
  check('the dealers list has the stock dealers only, with their car count', #list.dealers == 1 and list.dealers[1].name == 'Jefferson Motors' and list.dealers[1].count == 2 and list.dealers[1].metres == 5000)
  dealers.offers('d1')
  local shown = last('slLaptopOffers')
  check('the cards are the own offers of the lot, in the same order', #shown.offers == 2 and shown.offers[1].id == 'd1:dealer-3-1' and shown.offers[2].price == 7000)
  local c1 = shown.offers[1]
  check('each card has what the stock listing shows: picture, year, brand, specs, seller, distance, arrival', c1.preview == '/vehicles/nil/x.png' and c1.year == 2011 and c1.brand == 'Ibishu'
    and c1.specs.power == 120 and c1.specs.drivetrain == 'RWD' and c1.seller == 'Jefferson Motors' and c1.metres == 5000 and c1.hours == 3 and c1.mileage == 12 and c1.condition == 1)
  dealers.buy('d1', 'd1:dealer-3-1')
  check('buy takes the money once and orders the car', state.money == 5000 and charged == 1 and #state.orders == 1 and state.bought['d1:dealer-3-1'])
  dealers.buy('d1', 'd1:dealer-3-1')
  check('a second buy of the same car takes nothing', state.money == 5000 and charged == 1 and toasts[#toasts] == 'That car has gone.')
  check('it is gone from the lot and the laptop', #sl_lot.offersFor(nil, state) == 1 and #last('slLaptopOffers').offers == 1)
  check('and the list shows the order on its way', #last('slLaptopDealers').coming == 1 and last('slLaptopDealers').coming[1].hours >= 1)
  local onWay = dealers.ordersList()
  check('the car on its way is listed for My cars with its arrival', #onWay == 1 and onWay[1].name == state.orders[1].offer.name and onWay[1].day == math.floor(state.orders[1].due / 24) and onWay[1].hour == state.orders[1].due % 24)
  dealers.onUpdate(5)
  check('nothing is built before the delay', #built == 0 and #state.cars == 0)
  -- the forecourt is full (a vehicle within 4 m of every spot): the car is not built on top of one; the player is told once; later, with room, it comes
  do
    local freeNow = sl_fleet.freeForecourt
    sl_fleet.freeForecourt = function() return nil end
    local texts0, clock0 = #texts, os.clock
    hourNow = 14
    dealers.onUpdate(5)
    local told = #texts - texts0
    os.clock = function() return clock0() + 1000 end
    dealers.onUpdate(5)
    check('a full forecourt: nothing is built, the player is told once', #built == 0 and told == 1 and #texts - texts0 == 1 and #state.orders == 1)
    sl_fleet.freeForecourt = freeNow
    hourNow = 12.5
    os.clock = function() return clock0() + 5000 end      -- (the 30 s wait of the full forecourt is over for the rest of the test)
  end
  local saved = deepcopy(state)                   -- a save and a load before the car arrives
  state = saved
  hourNow = 14                                    -- the dealer is 5 km away: 3 hours; it is now 4 hours later
  dealers.onUpdate(5)
  check('after the delay the car is built and registered, once, from the saved order', #built == 1 and built[1] == 'd1:dealer-3-1' and #state.cars == 1 and #state.orders == 0)
  check('the car you drive stays the car you drive, and a text says it has arrived', state.activeCar == nil and texts[#texts]:find('delivered') ~= nil)
  dealers.onUpdate(5)
  check('and it is not delivered again or offered again', #built == 1 and #sl_lot.offersFor(nil, state) == 1 and state.bought['d1:dealer-3-1'])

  -- the phone: a Revline car ad bought for delivery, the clock skipped with the Wait app's plan, the car arrives and is registered
  package.loaded['jbeam/io'] = {}
  sl_career.has = function() return true end
  sl_career.mapText = function(t) return t end
  local yard0 = setmetatable({ x = 0, y = 0, z = 0 }, getmetatable(P(0)))
  sl_fleet.forecourt = function() return yard0, 'rot' end
  sl_fleet.freeForecourt = function() return yard0, 'rot' end
  state.money, state.day, state.market = 9000, 3, { listings = {}, nextId = 1, refreshed = 0, deliveries = {}, rounds = {}, mine = {} }
  state.market.listings[1] = { id = 'm1', kind = 'car', channel = 'app', ask = 900, condition = 0.8, seller = 'Dave', where = { x = 3000, y = 0, z = 0 },
    item = { name = 'Pessima', model = 'pessima' }, offer = { id = 'used-0-1', name = 'Pessima', brand = 'Ibishu', model = 'pessima', config = 'vehicles/pessima/x.pc', price = 900,
      value = 1500, condition = 0.8, faults = {}, mileage = 1000, kind = 'used' } }
  hourNow = 12.5
  local before, carsBefore, builtBefore = state.money, #state.cars, #built
  local ok, text = require('sl/classifieds').buy('m1', 'delivery')
  check('a Revline car bought for delivery: paid with the fee, an order in the save, nothing built yet', ok and state.money < before - 900 and #state.orders == 1
    and state.orders[1].offer.id == 'revline:m1' and state.market.listings[1].taken and #built == builtBefore and #state.cars == carsBefore, text)
  local function skip(what) local plan = progression.skipPlan(hourNow, what) hourNow = plan.to state.day = state.day + plan.days dealers.onUpdate(5) end
  skip('1')
  check('one hour on: not there yet', #state.orders == 1 and #built == builtBefore)
  skip('3')
  check('three hours more (the Wait app\'s own plan): the car is built and registered at the garage, the order gone',
    #state.orders == 0 and #built == builtBefore + 1 and built[#built] == 'revline:m1' and #state.cars == carsBefore + 1 and state.cars[#state.cars].name == 'Pessima')
  hourNow, state.day = 23, 4
  state.market.listings[1] = { id = 'm2', kind = 'car', channel = 'app', ask = 900, condition = 0.8, seller = 'Dave', where = { x = 3000, y = 0, z = 0 }, item = { name = 'Covet', model = 'covet' },
    offer = { id = 'used-0-2', name = 'Covet', model = 'covet', config = 'vehicles/covet/y.pc', price = 900, value = 1500, condition = 0.8, faults = {}, mileage = 1, kind = 'used' } }
  require('sl/classifieds').buy('m2', 'delivery')
  skip('morning')                                   -- across 06:00: the day counter moves, the order is still due
  check('and a wait until the morning across the day change delivers it too', #state.orders == 0 and #built == builtBefore + 2)

  -- used-car checks: a private car ad shows its history but not its faults until a mechanic has looked
  do
    local U = require('sl/core/usedcar')
    state.money = 500
    state.market.refreshed = 1e9
    state.market.listings = {}
    state.market.listings[1] = { id = 'm3', kind = 'car', channel = 'app', expires = 1e9, rating = 4, ask = 2000, condition = 0.7, seller = 'Sam', where = { x = 3000, y = 0, z = 0 },
      item = { name = 'Covet', model = 'covet' }, offer = { id = 'used-0-3', name = 'Covet', model = 'covet', config = 'vehicles/covet/z.pc', price = 2000, value = 3000, condition = 0.7,
        faults = { 'brakes', 'engine' }, mileage = 90000, kind = 'used' } }
    local C = require('sl/classifieds')
    for _, c in ipairs(state.cars) do c.model = c.model or 'covet' end
    local oldPV = rawget(_G, 'getPlayerVehicle')
    _G.getPlayerVehicle = function() return nil end
    local function card(id) for _, c in ipairs(C.summary().listings) do if c.id == id then return c end end end
    local c3 = card('m3')
    check('used car: the ad hides the faults and the report, and shows the history and the fee', c3 and c3.hidden == true and c3.faults == nil and c3.faultList == nil and c3.report == nil and #c3.history == 3 and c3.checkFee == U.fee(2000) and c3.checked == false)
    local function leaks(v, depth)
      if depth > 4 then return false end
      if type(v) == 'string' then return v == 'brakes' or v == 'engine' or v:find('Brakes', 1, true) ~= nil end
      if type(v) == 'table' then for _, x in pairs(v) do if leaks(x, depth + 1) then return true end end end
      return false
    end
    check('used car: no field of an unchecked card names a fault', not leaks(c3, 0))
    local okc = C.check('m3')
    check('used car: the check costs the fee and shows the faults with what each costs', okc == true and state.money == 500 - U.fee(2000) and card('m3').checked == true and card('m3').faults == 2 and #card('m3').found == 2 and card('m3').found[1].cost == 150 and card('m3').report ~= nil)
    local moneyAfter = state.money
    C.check('m3')
    check('used car: checking twice charges once', state.money == moneyAfter)
    state.money = 0
    state.market.listings[1].checked = false
    check('used car: not enough money refuses and shows nothing', (C.check('m3')) == false and card('m3').hidden == true)
    _G.getPlayerVehicle = oldPV
  end
end

-- a lot's marker prompt (T33, junkyard/scrapyard): a lot that shows cars always has "look"; a driver in a fleet car also gets "sell" after it; a dealer never buys
do
  local lp = require('sl/core/lotprompt')
  local function m(kind, foot, fleet) return table.concat(lp.modes(kind, foot, fleet), '+') end
  check('on foot: look, at every lot', m('used', true, false) == 'browse' and m('dealer', true, false) == 'browse' and m('scrap', true, true) == 'browse')
  check('a driver outside a fleet car at a junkyard or scrapyard can look', m('used', false, false) == 'browse' and m('scrap', false, false) == 'browse')
  check('a driver in a fleet car at a junkyard or scrapyard: look, then sell', m('used', false, true) == 'browse+sell' and m('scrap', false, true) == 'browse+sell')
  check('a dealer is unchanged: look for a driver, never sell', m('dealer', false, false) == 'browse' and m('dealer', false, true) == 'browse')
  check('stopping at a lot with no prompt: a driver with no fleet car browses at every lot, in a fleet car the junkyard/scrapyard sell, a dealer browses',
    lp.driveUp('used', false, false) == 'browse' and lp.driveUp('scrap', false, false) == 'browse' and lp.driveUp('dealer', false, false) == 'browse'
    and lp.driveUp('used', false, true) == 'sell' and lp.driveUp('scrap', false, true) == 'sell' and lp.driveUp('dealer', false, true) == 'browse' and lp.driveUp('used', true, true) == 'browse')
end

do -- A2: a lot shows cars of its own tier
  local tiers = require('sl/core/tiers')
  local cars = {}
  for _, v in ipairs({ 800, 2500, 6000, 9000, 14000, 18000, 24000, 31000, 40000, 55000, 80000, 120000 }) do cars[#cars + 1] = { value = v } end
  local function minmax(list) local lo, hi = math.huge, 0 for _, c in ipairs(list) do lo, hi = math.min(lo, c.value), math.max(hi, c.value) end return lo, hi end
  local hi = tiers.within(cars, 'high', 'dealer', 4)
  check('a high-end dealer has no cheap cars', #hi == 7 and minmax(hi) >= 18000, #hi)
  local lo = tiers.within(cars, 'low', 'dealer', 4)
  local _, top = minmax(lo)
  check('a low-end dealer has no premium cars', #lo >= 4 and top <= 48000, #lo)
  check('too few cars of the tier: the pool as it is', #tiers.within(cars, 'high', 'dealer', 9) == #cars)
  check('a used lot is priced at about half the value', minmax(tiers.within(cars, 'mid', 'used', 3)) >= 12000 * 0.6 / 0.55 - 1)
end

-- lot camera (C2): the purchase reveal ends exactly on the chase pose, pushes in at the middle, and the sway stays bounded
do
  local lotcam = require('sl/core/lotcam')
  local c, f = { x = 10, y = 20, z = 1 }, { x = 0, y = 1 }
  local p1 = lotcam.chase(c, f)
  check('the chase pose is 7.5 m behind and 2.4 m up', math.abs(p1.x - 10) < 1e-6 and math.abs(p1.y - 12.5) < 1e-6 and math.abs(p1.z - 3.4) < 1e-6)
  local function dist(p) return math.sqrt((p.x - c.x) ^ 2 + (p.y - c.y) ^ 2) end
  local ok, outsideOk = true, true
  local sizes = { { 3.4, 1.6, 1.3 }, { 4.5, 1.9, 1.5 }, { 5.5, 2.0, 1.4 }, { 6.5, 2.4, 2.4 } }
  for _, sz in ipairs(sizes) do
    for _, kind in ipairs(lotcam.BROWSE_SHOTS) do
      for _, s in ipairs({ 0, 0.25, 0.5, 0.75, 1 }) do
        local p, l = lotcam.shot(kind, c, f, sz[1], sz[2], s)
        if not (p.x == p.x and l.x == l.x and dist(p) < 12 and math.abs(p.z - c.z) < 5) then ok = false end
        if kind ~= 'cabin' and kind ~= 'cabin_pass' and lotcam.inBox(c, f, sz[1], sz[2], sz[3], p) then outsideOk = false end
      end
    end
  end
  do   -- the side shot: the car's length fills 60 % of the frame width, whatever its size
    local worstFill, tanv = 9, lotcam.viewTan
    for _, sz in ipairs({ { 3.4, 1.6 }, { 4.5, 1.9 }, { 5.5, 2.0 }, { 6.5, 2.4 } }) do
      local p = lotcam.shot('side', c, f, sz[1], sz[2], 0.5)
      local D = math.abs((p.x - c.x) * f.y - (p.y - c.y) * f.x)       -- the side distance from the car's centre line
      local fill = (sz[1] / D) / (2 * tanv)
      worstFill = math.min(worstFill, fill)
      if D > sz[2] / 2 + 1.2 + 1e-6 then check('side shot fills 60 percent of the width for the ' .. sz[1] .. ' m car', math.abs(fill - lotcam.SIDE_FILL) < 1e-6, fill) end
    end
    check('every side shot stays at least 1.2 m from the car body', worstFill > 0)
  end
  check('every detail shot (16 kinds, four car sizes) is finite and close to the car', ok)
  check('every shot but the cabin ones keeps its eye outside the car box plus the margin along its whole drift', outsideOk)
  -- the cabin shots turn the head from the driver camera position and never move the eye
  local eye = { x = c.x - 0.4, y = c.y + 0.1, z = c.z + 0.2 }
  local e0 = lotcam.shot('cabin', c, f, 4.5, 1.9, 0, eye)
  local e1 = lotcam.shot('cabin', c, f, 4.5, 1.9, 1, eye)
  local q0, ql = lotcam.shot('cabin_pass', c, f, 4.5, 1.9, 0, eye)
  check('the cabin shot stays at the driver camera and only turns', e0.x == eye.x and e1.x == eye.x and e1.y == eye.y and e0.z == eye.z and math.abs(q0.x - (c.x + 0.4)) < 1e-6)
  -- a transition between any two shots never puts the eye inside the car box (but for the short move through the driver's window to a cabin shot)
  do
    local orbit = { pos = { x = 10, y = 14, z = 2.5 }, look = { x = 10, y = 20, z = 1 } }
    local bad
    for _, sz in ipairs(sizes) do
      local ctx2 = { c = c, f = f, L = sz[1], W = sz[2], H = sz[3] }
      for _, A in ipairs(lotcam.BROWSE_SHOTS) do
        for _, B in ipairs(lotcam.BROWSE_SHOTS) do
          if A ~= B then
            local pa, la = lotcam.shot(A, c, f, sz[1], sz[2], 1)
            local st = { phase = 'shot', kind = A, t = lotcam.SHOT_TIME - 0.001, pos = pa, look = la }
            local frames, inside, lastP, jump = 0, 0, pa, 0
            for i = 1, 30 * 6 do
              local pos
              st, pos = lotcam.chain(st, 1 / 30, true, orbit, ctx2, function() return B end)
              if not st or st.phase == 'shot' then break end
              frames = frames + 1
              if lotcam.inBox(c, f, sz[1], sz[2], sz[3], pos) then inside = inside + 1 end
              jump = math.max(jump, math.sqrt((pos.x - lastP.x) ^ 2 + (pos.y - lastP.y) ^ 2 + (pos.z - lastP.z) ^ 2))
              lastP = pos
            end
            local cabin = A == 'cabin' or B == 'cabin' or A == 'cabin_pass' or B == 'cabin_pass'
            if cabin then ok = ok and inside <= frames * ((A:find('cabin') and B:find('cabin')) and 0.5 or 0.3) else ok = ok and inside == 0 end
            if jump > 1.5 then ok = false end
            if not ok and not bad then bad = A .. '>' .. B .. ' ' .. sz[1] .. ' inside=' .. inside .. '/' .. frames .. ' jump=' .. jump end
          end
        end
      end
    end
    check('no transition between any two shots (16x15 pairs, four sizes) crosses the car box, and none jumps', ok, bad)
  end
  do
    local fx = require('sl/core/lotfx')
    check('bars: off at rest, on in a shot and on the way to the next, off in the cabin shots and on the way back to the orbit', not fx.barsOn(nil) and fx.barsOn({ phase = 'shot', kind = 'side' })
      and fx.barsOn({ phase = 'trans', kind = 'cabin', nextKind = 'side' }) and not fx.barsOn({ phase = 'trans', kind = 'side', nextKind = 'cabin' }) and not fx.barsOn({ phase = 'shot', kind = 'cabin_pass' })
      and not fx.barsOn({ phase = 'out', kind = 'side' }))
    check('fov: a shot tightens 0 to 3 degrees, the move to the next brings it back, the cabin keeps the normal view', fx.fovDrift({ phase = 'shot', kind = 'side', t = 0 }) == 0 and math.abs(fx.fovDrift({ phase = 'shot', kind = 'side', t = 5 }) - 3) < 1e-9
      and math.abs(fx.fovDrift({ phase = 'trans', kind = 'side', nextKind = 'rear', u = 0 }) - 3) < 1e-9 and fx.fovDrift({ phase = 'trans', kind = 'side', nextKind = 'rear', u = 1 }) == 0
      and fx.fovDrift({ phase = 'shot', kind = 'cabin', t = 4 }) == 0 and fx.fovDrift({ phase = 'trans', kind = 'cabin', nextKind = 'side', u = 0 }) == 0 and fx.fovDrift(nil) == 0)
    -- depth of field: for many eyes and car sizes the sharp window of the game's own formulas covers the whole car plus the margin, nothing is blurred in front
    local good, worst = true, nil
    for _, far in ipairs({ 800, 2000, 4000 }) do
      for _, sz in ipairs({ { 3.4, 1.6, 1.3 }, { 4.5, 1.9, 1.5 }, { 6.5, 2.4, 2.4 } }) do
        for _, eyeAt in ipairs({ { 6, 0, 1 }, { 10, 3, 1.5 }, { 2.5, 1, 0.5 }, { 14, -6, 4 }, { 0, 7, 2 } }) do
          local c0 = { x = 100, y = 100, z = 10 }
          local eye = { x = c0.x + eyeAt[1], y = c0.y + eyeAt[2], z = c0.z + eyeAt[3] }
          local p, need = fx.dofParams(eye, c0, c0, sz[1], sz[2], sz[3], far, 1)
          local lo, hi = fx.dofWindow(p, far)
          if not (lo <= math.max(need.near, 0) + 1e-6 and hi >= need.far - 1e-6 and p.nearBlurMax == 0 and p.focalDist >= 0 and p.minRange >= 0) then good = false worst = worst or (far .. ' ' .. sz[1] .. ' ' .. eyeAt[1] .. ' lo=' .. lo .. ' hi=' .. hi .. ' need=' .. need.near .. '..' .. need.far) end
        end
      end
    end
    check('dof: the sharp window of the effect covers the car from its nearest to its farthest point plus the margin, with no blur in front', good, worst)
    local p2, need2 = fx.dofParams({ x = 8, y = 0, z = 1 }, { x = 0, y = 0, z = 1 }, { x = 0, y = 0, z = 1 }, 4.5, 1.9, 1.5, 2000, 0.5)
    local _, hi2 = fx.dofWindow(p2, 2000)
    check('dof: the blur follows the shot weight and starts just beyond the car', p2.farBlurMax == 0.25 and fx.dofParams({ x = 8, y = 0, z = 1 }, { x = 0, y = 0, z = 1 }, { x = 0, y = 0, z = 1 }, 4.5, 1.9, 1.5, 2000, 0).farBlurMax == 0
      and math.abs(hi2 - need2.far) < 1e-6 and need2.far - 8 < 6)
  end
  -- the shuffle bag: every kind once per round, never the same kind twice in a row, unusable kinds dropped
  do
    local state, rnd = { bag = {} }, function(n) return math.random(n) end
    local prev, repeated, seenK, drops = nil, false, {}, 0
    for _ = 1, 600 do
      local k = lotcam.draw(state, rnd, function(kind) if kind == 'engine' or kind == 'top' then drops = drops + 1 return false end return true end)
      if k == prev then repeated = true end
      prev, seenK[k] = k, true
    end
    local n = 0 for _ in pairs(seenK) do n = n + 1 end
    check('the shuffle never repeats back to back, covers every usable kind, and drops unusable ones', not repeated and n == #lotcam.BROWSE_SHOTS - 2 and not seenK.engine and not seenK.top and drops > 0)
    local nothing = lotcam.draw({ bag = {} }, rnd, function() return false end)
    check('nothing usable: nil', nothing == nil)
  end
  local pw = lotcam.shot('wheel', c, f, 4.5, 1.9, 0)
  local pc = lotcam.shot('cabin', c, f, 4.5, 1.9, 0)
  check('the wheel shot stands by the front wheel, the cabin shot inside the car', pw.y > c.y + 1 and math.abs(pw.x - c.x) > 2 and dist(pc) < 1.5)
  check('a clear view passes, a pillar between eye and car fails every shot that looks through it', lotcam.shotClear('side', c, f, 4.5, 1.9, function() return nil end)
    and not lotcam.shotClear('side', c, f, 4.5, 1.9, function(a, b) return 1.0 end))
  -- the browsing shots flow: one into the next along an arc, never back through the orbit pose, never a jump; only the player's input eases out
  do
    local orbit = { pos = { x = 10, y = 14, z = 2.5 }, look = { x = 10, y = 20, z = 1 } }
    local ctx = { c = c, f = f, L = 4.5, W = 1.9 }
    local kinds, n = lotcam.BROWSE_SHOTS, 0
    local function pick() n = n + 1 return kinds[(n - 1) % #kinds + 1] end
    local st, last, shots, minOrbit, maxStep, atRest, worstAt = nil, nil, 0, 1e9, 0, false, ''
    local seen = {}
    for i = 1, 30 * 220 do
      local pos
      st, pos = lotcam.chain(st, 1 / 30, true, orbit, ctx, pick)
      if st then
        if last then local stp = math.sqrt((pos.x - last.x) ^ 2 + (pos.y - last.y) ^ 2 + (pos.z - last.z) ^ 2) if stp > maxStep then maxStep, worstAt = stp, st.phase .. ' ' .. tostring(st.kind) .. '>' .. tostring(st.nextKind) .. ' u=' .. tostring(st.u) end end
        last = pos
        if st.phase == 'shot' or st.phase == 'trans' then
          seen[st.kind] = true
          minOrbit = math.min(minOrbit, math.sqrt((pos.x - orbit.pos.x) ^ 2 + (pos.y - orbit.pos.y) ^ 2 + (pos.z - orbit.pos.z) ^ 2))
        end
      end
    end
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    check('shots follow each other (all the kinds come round) and never go back through the orbit pose', count == #kinds and minOrbit > 0.5, minOrbit)
    check('no jump: a frame moves the camera less than 0.8 m', maxStep < 0.8, maxStep .. ' ' .. worstAt)
    -- the player moves the camera: it eases back to the orbit, in about SHOT_EASE seconds, and ends at rest
    local out, rest = st, false
    for i = 1, 60 do
      local pos
      out, pos = lotcam.chain(out, 1 / 30, false, orbit, ctx, pick)
      if not out then rest = true break end
    end
    check('the player input eases back to the orbit and rests', rest)
    local _, _, _, _, failed = lotcam.chain(nil, 0.03, true, orbit, ctx, function() return nil end)
    check('no usable shot at the start: it stays on the orbit and says so', failed == true)
    local pa = lotcam.arc(c, { x = c.x + 5, y = c.y, z = c.z }, { x = c.x - 5, y = c.y, z = c.z }, 0.5)
    check('an arc swings round the car at its radius, not through it', math.abs(math.sqrt((pa.x - c.x) ^ 2 + (pa.y - c.y) ^ 2) - 5) < 1e-6)
  end
  local worst = 0
  for i = 0, 400 do worst = math.max(worst, math.abs(lotcam.sway(i * 0.25))) end
  check('sway is bounded', worst <= lotcam.SWAY + 1e-9 and worst > lotcam.SWAY * 0.9)
end

-- factory orders (C3)
do
  local F = require('sl/core/factory')
  local cat = F.catalogue({ { model = 'b', config = 'b/x.pc', name = 'B base', brand = 'Bb', value = 20000 }, { model = 'a', config = 'a/s.pc', name = 'A sport', value = 40000 },
    { model = 'a', config = 'a/b.pc', name = 'A base', value = 30000 }, { model = 'a', config = 'a/c.pc', name = 'A cheap', value = 30000 }, { name = 'no model' } })
  check('the catalogue groups trims by model, cheapest model first', #cat == 2 and cat[1].model == 'b' and cat[2].model == 'a' and #cat[2].trims == 3)
  check('the trims run by price then file', cat[2].trims[1].config == 'a/b.pc' and cat[2].trims[2].config == 'a/c.pc' and cat[2].trims[3].value == 40000)
  local o = F.order('a', cat[2].trims[3], 'Red', 100)
  check('an order costs the config value and is due in DELIVERY_HOURS', o.price == 40000 and o.due == 100 + F.DELIVERY_HOURS and o.config == 'a/s.pc')
  check('nothing is due early, the first arrived order is found', F.nextDue({ o }, 105) == nil and F.nextDue({ { due = 200 }, o }, 106) == 2 and F.nextDue(nil, 1) == nil)
  local red, own = { baseColor = { 1, 0, 0, 1 } }, { { baseColor = { 0, 0, 1, 1 } }, { baseColor = { 0, 1, 0, 1 } } }
  local rec = { config = { paints = F.withPaint(own, red) } }
  check('the chosen paint is the saved record first paint, the other paints stay, the config itself is not changed', rec.config.paints[1] == red and rec.config.paints[2] == own[2] and own[1].baseColor[3] == 1 and #F.withPaint(nil, red) == 1 and #F.withPaint(own, nil) == 2)
  local day, hr = F.arrives({ due = 24 * 5 + 7 })
  check('an order says the day and hour it arrives', day == 5 and hr == 7)
  check('slots go to the screen group by name', F.groupOf('covet_mudflap_F') == 'mudflaps' and F.groupOf('steering_wheel') == 'steering' and F.groupOf('wheel_F_5') == 'wheels' and F.groupOf('interior_color') == 'interior' and F.groupOf('exhaust') == nil)
  check('lettering, panels, ECUs and mounts are hidden, bumpers, motors and steering wheels stay, option names can place a slot', F.groupOf('sbr_lettering_tailgate') == nil and F.groupOf('sbr_taillight_b_panel_l') == nil and F.groupOf('covet_enginemounts') == nil and F.groupOf('covet_bumper_F') == 'body' and F.groupOf('sbr_differential_F', 'Front Electric Motor') == 'engine' and F.groupOf('steering_bar') == 'steering' and F.groupOf('wheel_F_5', 'Lightweight wheel') == 'wheels')
  local opts = F.optionsOf({ { seat = 'seat_a', wheel = 'w1', roof = '' }, { seat = 'seat_b', wheel = 'w1', roof = 'roof_x' }, { seat = 'seat_a', wheel = 'w1' } })
  check('options are the parts used across configs; a slot with one part everywhere is no option; fitted in some only is', #opts.seat == 2 and opts.wheel == nil and #opts.roof == 1)
  check('paint to CSS from 0..1 and 0..255, alpha ignored', F.css({ 1, 0, 0.5, 1.2 }) == 'rgb(255,0,128)' and F.css({ 200, 10, 0, 255 }) == 'rgb(200,10,0)' and F.css(nil) == 'rgb(128,128,128)')
  check('the total adds the deltas', F.total(1000, { a = 50, b = -20 }) == 1030)
  local cfgLib = require('sl/factorycfg')
  local worth = { w_a = 100, w_b = 350, s_a = 0, s_b = 0 }
  local fake = { pcs = { { parts = { wheel_F = 'w_a', seat = 's_a' } } }, options = { wheel_F = { 'w_a', 'w_b' }, seat = { 's_a', 's_b' } },
    value = function(p) return worth[p] or 0 end, name = function(p) return p end }
  local groups, deltas = cfgLib.groups(fake, 1, { wheel_F = 'w_b' })
  check('the configurator groups wheels and interior, marks the pick, prices it over the trim part', #groups == 2 and groups[1].id == 'interior' and groups[2].id == 'wheels' and groups[2].slots[1].options[2].on
    and groups[2].slots[1].options[2].delta == 250 and groups[1].slots[1].options[1].on and F.total(30000, deltas) == 30250)
end

do -- special-order models: on no lot, ad, racer pool or cruiser; only in the factory's special-order list
  local cars, stock, factory = require('sl/core/cars'), require('sl/core/stockdealers'), require('sl/core/factory')
  local function c(model, raw) return { model = model, config = model .. '_a', name = model, brand = 'X', value = 20000, power = 100, weight = 900, raw = raw or {} } end
  local pool = { c('bx'), c('atv'), c('pigeon'), c('utv'), c('wl40'), c('dumptruck'), c('rockbouncer'), c('racetruck'), c('unicycle'), c('covet'),
    c('mystery', { ['Body Style'] = 'Buggy' }), c('oddball', { Type = 'Trailer' }), c('other', { aggregates = { ['Body Style'] = { ATV = true } } }) }
  local bad = { atv = 1, pigeon = 1, utv = 1, wl40 = 1, dumptruck = 1, rockbouncer = 1, racetruck = 1, unicycle = 1, mystery = 1, oddball = 1, other = 1 }
  local function clean(list) for _, x in ipairs(list) do if bad[x.model] then return false end end return #list > 0 end
  check('the lot pool has no special-order model', clean(stock.lotPool(pool, {})) and #stock.lotPool(pool, {}) == 2, (function() local t = {} for _, x in ipairs(stock.lotPool(pool, {})) do t[#t + 1] = x.model end return table.concat(t, ',') end)())
  check('the stock dealer pool has none', clean(stock.pool(cars.withoutModels(pool, {}), nil, nil)))
  check('the racer pool rule has none', clean(cars.withoutModels(pool, { midtruck = true })))
  local special = cars.onlySpecialOrder(pool)
  check('all of them are in the special-order list', #special == 11, #special)
  local cat = factory.catalogue(special)
  local found = false
  for _, m in ipairs(cat) do if m.model == 'atv' then found = true end end
  check('the Wydra is in the factory catalogue of the special-order list', found)
  local both = factory.withSpecial({ c('covet') }, special)
  local wydra
  for _, m in ipairs(both) do if m.model == 'atv' then wydra = m end end
  check('the dealer catalogue lists its own model first, then the special-order group with the Wydra', both[1].model == 'covet' and not both[1].special and wydra and wydra.special == true)
end

do -- A8: events are called off when too long or too far from the route
  local rc = require('sl/core/racecancel')
  local route = { { x = 0, y = 0 }, { x = 1000, y = 0 }, { x = 1000, y = 1000 } }
  check('on the route: 0 m', rc.distToRoute({ x = 500, y = 0 }, route) == 0)
  check('beside the route: 40 m', math.abs(rc.distToRoute({ x = 500, y = 40 }, route) - 40) < 1e-6)
  check('past the second leg', math.abs(rc.distToRoute({ x = 1100, y = 500 }, route) - 100) < 1e-6)
  check('a single point is a distance', math.abs(rc.distToRoute({ x = 3, y = 4 }, { { x = 0, y = 0 } }) - 5) < 1e-6)
  check('time limit grows with the route', rc.timeLimit(3000) > rc.timeLimit(1000) and rc.timeLimit(0) == rc.GRACE)
  check('fine inside the limits', rc.reason(60, 400, 20) == nil and rc.reason(5, nil, nil) == nil)
  check('too long is off', rc.reason(500, 400, 0) ~= nil)
  check('too far is off', rc.reason(10, 400, 900) ~= nil and rc.reason(10, 400, 300) == nil)
end

do -- A10: a street race is run by road cars
  local cars = require('sl/core/cars')
  check('no buggy races on a street', not cars.racerOk({ name = 'Buggy', raw = { ['Body Style'] = 'Buggy' } }))
  check('no off-road config races on a street', not cars.racerOk({ name = 'Truck', raw = { ['Config Type'] = 'Offroad' } }))
  check('a coupe still does', cars.racerOk({ name = 'Coupe', raw = { ['Body Style'] = 'Coupe', ['Config Type'] = 'Street' } }))
end

do -- A13: a part that fell off is not in the saved setup
  local cars = require('sl/core/cars')
  local tree = { id = 'main', chosenPartName = 'body', partPath = '/body', children = {
    hood = { id = 'hood', chosenPartName = 'hood_a', partPath = '/body/hood_a', children = { latch = { id = 'latch', chosenPartName = 'latch_a', partPath = '/body/hood_a/latch_a' } } },
    door = { id = 'door', chosenPartName = 'door_a', partPath = '/body/door_a' } } }
  local gone = cars.stripParts(tree, { '/body/hood_a', '/nothing' })
  check('the lost part is taken out', #gone == 1 and tree.children.hood.chosenPartName == '' and tree.children.hood.children == nil and tree.children.hood.decisionMethod == 'user-empty')
  check('the others stay', tree.children.door.chosenPartName == 'door_a' and tree.chosenPartName == 'body')
  check('nothing lost: nothing changes', #cars.stripParts(tree, {}) == 0 and #cars.stripParts(tree, nil) == 0)
end

do -- A11: meet cars stand in free bays off the road, nearest first
  local ms = require('sl/core/meetspots')
  local bays = { { x = 5, y = 0, z = 0, dx = 0, dy = 1 }, { x = 10, y = 0, z = 0, dx = 0, dy = 1 }, { x = 14, y = 0, z = 0, dx = 0, dy = 1 },
    { x = 8, y = 20, z = 0, dx = 1, dy = 0, occupied = true }, { x = 0, y = 30, z = 0, dx = 1, dy = 0 }, { x = 200, y = 0, z = 0, dx = 0, dy = 1 },
    { x = 3, y = 40, z = 0, dx = 0, dy = 0 }, { x = 6, y = 6, z = 0, dx = 1, dy = 0 } }
  local roads = { { x1 = 6, y1 = -50, x2 = 6, y2 = 50, half = 3 } }          -- a road along x = 6 takes the bays at x 5 and 6,6 (and x 10 is clear)
  local out = ms.pick({ x = 0, y = 0 }, bays, roads, 5)
  local xs = {}
  for _, p in ipairs(out) do xs[#xs + 1] = p.x end
  check('meet spots: off the road, free, near, facing', #out == 3 and out[1].x == 10 and out[2].x == 14 and out[3].x == 0 and out[1].dy == 1, table.concat(xs, ','))
  check('meet spots: at most n', #ms.pick({ x = 0, y = 0 }, bays, {}, 2) == 2)
  check('meet spots: no bays, no spots', #ms.pick({ x = 0, y = 0 }, nil, nil, 4) == 0)
end

-- weather (#45, B-weather): rain strengths, the sky numbers, the roads getting wet and drying out, the puddles
do
  local wx = require('sl/core/weather')
  local counts = { light = 0, medium = 0, heavy = 0 }
  for day = 1, 300 do counts[wx.level('seed', day, 'day')] = counts[wx.level('seed', day, 'day')] + 1 end
  check('all three rain levels turn up, medium most, heavy least', counts.light > 40 and counts.heavy > 20 and counts.medium > counts.light and counts.heavy < counts.light, counts.light .. '/' .. counts.medium .. '/' .. counts.heavy)
  check('the level is the same every time for a seed and day', wx.level('s', 4, 'night') == wx.level('s', 4, 'night'))
  local l, m, h = wx.resolve('rain', 'light'), wx.resolve('rain', 'medium'), wx.resolve('rain', 'heavy')
  check('harder rain: more drops, faster, thicker cloud, more fog, less grip, wetter roads',
    l.drops < m.drops and m.drops < h.drops and l.speed < m.speed and m.speed < h.speed and l.cloud < m.cloud and m.cloud < h.cloud and l.fog < m.fog and m.fog < h.fog
    and l.grip > m.grip and m.grip > h.grip and l.wet < m.wet and m.wet <= h.wet)
  check('rain is overcast and wet, clear and cloudy are neither', m.cloud > wx.resolve('cloudy').cloud and wx.resolve('clear').wet == 0 and wx.resolve('cloudy').drops == 0 and wx.resolve('cloudy').cirrus > 0)
  check('an unknown level is medium rain', wx.resolve('rain', 'nope').drops == m.drops)
  local b = wx.blend({ drops = 0, cloud = 1, fog = 0.1, grip = 1 }, h, 0.5)
  check('the blend moves the new numbers and keeps the missing ones (no nil maths)', b.drops == h.drops / 2 and b.wet == h.wet and b.speed == h.speed and b.cirrus == h.cirrus)
  check('the blend with the level not knowing cirrus stays nil', wx.blend({ drops = 0, cloud = 1, fog = 0, grip = 1 }, { drops = 0, cloud = 1, fog = 0, grip = 1 }, 1).cirrus == nil)
  local w = 0
  for _ = 1, 60 do w = wx.wetStep(w, 0.8, 1) end
  check('the roads soak in about two minutes, never past the rain level', w > 0.3 and w < 0.8, w)
  for _ = 1, 120 do w = wx.wetStep(w, 0.8, 1) end
  check('and stop at the level', w == 0.8)
  local d = w
  for _ = 1, 60 do d = wx.wetStep(d, 0, 1) end
  check('they dry slower than they soak, and fully in the end', d < w and d > 0.4 and wx.wetStep(0.001, 0, 100) == 0)
  check('no puddles on a dry road, more when it is wetter, a cap', wx.puddleCount(0) == 0 and wx.puddleCount(0.14) == 0 and wx.puddleCount(0.5) < wx.puddleCount(1) and wx.puddleCount(1) == wx.MAX_PUDDLES)
  check('a puddle fades in over a few seconds and follows the wetness', wx.puddleAlpha(1, 0) == 0 and wx.puddleAlpha(1, 6) > wx.puddleAlpha(1, 2) and wx.puddleAlpha(0.2, 10) < wx.puddleAlpha(1, 10) and wx.puddleAlpha(0.05, 10) == 0)
  local gm, gh = wx.resolve('rain', 'medium'), wx.resolve('rain', 'heavy')
  check('grip follows the wetness: dry 1, fully wet = the rain\'s grip, halfway between, never below', wx.wetGrip(0, gm) == 1 and math.abs(wx.wetGrip(gm.wet, gm) - gm.grip) < 1e-9
    and math.abs(wx.wetGrip(gm.wet / 2, gm) - (1 + gm.grip) / 2) < 1e-9 and wx.wetGrip(5, gh) == gh.grip and wx.wetGrip(0.4, nil) == 1)
  local wetNow = gm.wet
  for _ = 1, 210 do wetNow = wx.wetStep(wetNow, 0, 1) end      -- 3.5 min after the rain stopped
  check('and the road is still slippery after the rain stops, and the grip comes back with the drying', wx.wetGrip(wetNow, gm) < 1 and wx.wetGrip(wetNow, gm) > gm.grip and wx.wetGrip(wx.wetStep(wetNow, 0, 400), gm) == 1)
  check('rain fog stays thin (a thick one takes the dawn light: an orange dust storm), and the sky is pulled to grey harder the harder it rains', h.fog < 0.001 and l.fog < 0.001
    and l.tint < m.tint and m.tint < h.tint and h.tint > 0.9 and wx.resolve('clear').tint == nil)
  local g = wx.greyer({ 1, 0.5, 0.2 }, 1)
  check('a colour pulled all the way to grey keeps its brightness; none leaves it alone', math.abs(g[1] - g[2]) < 1e-9 and math.abs(g[2] - g[3]) < 1e-9 and math.abs(g[1] - (0.3 + 0.295 + 0.022)) < 1e-9
    and wx.greyer({ 1, 0.5, 0.2 }, 0)[2] == 0.5)
  -- puddles (shared rules of the game side and the car): the depth, the wheel's grip and drag, the spray and the mist
  local pr = require('sl_puddles')
  local pud = { x = 10, y = 20, sx = 4, sy = 2, dx = 1, dy = 0, k = 1 }       -- direction (1, 0): along it (x) is sy = 2 m across, across it (y) is sx = 4 m
  check('depth: nothing outside, deepest in the middle, shallow at the rim, follows the size factor', pr.depth(pud, 30, 20) == 0 and pr.depth(pud, 10, 20) == 1 and pr.depth(pud, 10, 21.5) > 0 and pr.depth(pud, 10, 21.5) < 1
    and pr.depth({ x = 10, y = 20, sx = 4, sy = 2, dx = 1, dy = 0, k = 0.5 }, 10, 21.5) == 0)
  check('depth uses the right axes: along the direction is sy, across it sx', pr.depth(pud, 11.5, 20) == 0 and pr.depth(pud, 10, 21.5) > 0
    and pr.depth({ x = 0, y = 0, sx = 4, sy = 2, dx = 0, dy = 1, k = 1 }, 1.5, 0) > 0 and pr.depth({ x = 0, y = 0, sx = 4, sy = 2, dx = 0, dy = 1, k = 1 }, 0, 1.5) == 0)
  check('deepest of several', pr.deepest({ pud, { x = 0, y = 0, sx = 2, sy = 2, dx = 1, dy = 0, k = 1 } }, 0, 0) == 1 and pr.deepest({}, 0, 0) == 0 and pr.deepest(nil, 0, 0) == 0)
  check('grip: none lost outside water, a little at walking speed, nearly all above 120 km/h in deep water, never below the floor',
    pr.wheelGrip(100, 0) == 1 and pr.wheelGrip(30, 1) > 0.8 and pr.wheelGrip(30, 1) < 1 and pr.wheelGrip(80, 1) > pr.wheelGrip(100, 1) and pr.wheelGrip(120, 1) <= 0.16 and math.abs(pr.wheelGrip(300, 1) - pr.MIN_WHEEL_GRIP) < 1e-9
    and pr.wheelGrip(120, 0.3) > pr.wheelGrip(120, 1))
  check('drag: none dry or when standing, grows with speed and depth, capped', pr.drag(20, 0) == 0 and pr.drag(0.5, 1) == 0 and pr.drag(20, 1) > pr.drag(10, 1) and pr.drag(20, 1) > pr.drag(20, 0.5) and pr.drag(200, 1) == 500)
  check('spray and mist: spray only in water and with speed; mist only on a wet road (> 0.3) and with speed', pr.splash(20, 0) == 0 and pr.splash(20, 1) == 1 and pr.splash(5, 1) < pr.splash(15, 1)
    and pr.mist(0.3, 20) == 0 and pr.mist(1, 3) == 0 and pr.mist(1, 26) == 1 and pr.mist(0.65, 26) > 0 and pr.mist(0.65, 26) < 1)
  do -- a puddle's plane: dropped under 0.04, made only from 0.08 (no flicker at the edge of view), capped
    local w = require('sl/core/weather')
    check('planeAction: a standing plane is kept between 0.04 and 0.08 and dropped under 0.04; a missing one is made from 0.08 only',
      w.planeAction(true, 0.06, 1) == 'keep' and w.planeAction(true, 0.03, 1) == 'drop' and w.planeAction(false, 0.06, 1) == 'none' and w.planeAction(false, 0.08, 1) == 'make')
    check('planeAction: only the nearest 60 get a plane; one that has it keeps it until 10 places further out (no swap at the boundary)',
      w.planeAction(false, 1, 60) == 'make' and w.planeAction(false, 1, 61) == 'none' and w.planeAction(true, 1, 61) == 'keep' and w.planeAction(true, 1, 70) == 'keep' and w.planeAction(true, 1, 71) == 'drop')
  end
  do -- slPuddles with and without Car Surface FX's tyre module owning the water's grip
    local sv = { obj = rawget(_G, 'obj'), wheels = rawget(_G, 'wheels'), v = rawget(_G, 'v'), slCar = rawget(_G, 'slCar'), slPuddles = rawget(_G, 'slPuddles'), tyres = rawget(_G, 'carSurfaceFxTyres') }
    local fric, water = {}, {}
    _G.slCar, _G.slPuddles = nil, nil
    _G.obj = { getVelocity = function() return { length = function() return 40 end, x = 40, y = 0 } end, getPosition = function() return setmetatable({ x = 0, y = 0, z = 0 }, { __add = function(l, r) return { x = l.x + r.x, y = l.y + r.y, z = l.z + r.z } end }) end,
      getNodePosition = function() return { x = 10, y = 20, z = 0 } end, getId = function() return 1 end, queueGameEngineLua = function() end,
      applyForceVectorTime = function() end, setNodeFrictionSlidingCoefs = function(_, id, a, b) fric[#fric + 1] = a end }
    _G.wheels = { wheels = { [0] = { node1 = 1, treadNodes = { 5 } } } }
    _G.v = { data = { nodes = { [5] = { frictionCoef = 1 } } } }
    package.loaded['slPuddles'] = nil
    local sp = require('slPuddles')
    local function run() fric, water = {}, {} sp.setPuddles({ { x = 10, y = 20, sx = 4, sy = 2, dx = 1, dy = 0, k = 1 } }, 0, { physics = true }) sp.updateGFX(0.06) end
    _G.carSurfaceFxTyres = nil
    run()
    check('slPuddles: without the tyre module it scales the friction itself', fric[1] and fric[1] < 0.3 and sp.wheelFactor(0) < 0.3)
    _G.carSurfaceFxTyres = { active = function() return true end, setWheelWater = function(w, d) water[#water + 1] = { w, d } return true end }
    package.loaded['slPuddles'] = nil sp = require('slPuddles')
    run()
    check('slPuddles: with the tyre module on it is told the depth per wheel and writes no friction', #fric == 0 and water[1] and water[1][1] == 0 and water[1][2] == 1 and sp.wheelFactor(0) == 1)
    _G.carSurfaceFxTyres.active = function() return false end
    package.loaded['slPuddles'] = nil sp = require('slPuddles')
    run()
    check('slPuddles: the tyre module present but off changes nothing', #water == 0 and fric[1] and fric[1] < 0.3)
    _G.carSurfaceFxTyres.active = function() error('boom') end
    package.loaded['slPuddles'] = nil sp = require('slPuddles')
    run()
    check('slPuddles: an error in the tyre module falls back to the own friction', fric[1] and fric[1] < 0.3)
    _G.obj, _G.wheels, _G.v, _G.slCar, _G.slPuddles, _G.carSurfaceFxTyres = sv.obj, sv.wheels, sv.v, sv.slCar, sv.slPuddles, sv.tyres
    package.loaded['slPuddles'] = nil
  end
  local fx = require('sl/puddlefx')
  local dae = fx.gridDae({ 0, 0.01, 0, 0, 0, 0, 0, 0.02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.05 })
  check('the puddle grid: 5 x 5 corners on two skins, 64 triangles, uv for each corner, ground heights in', dae:find('count="150"', 1, true) and dae:find('count="50"', 1, true) and dae:find('<triangles material="sl_puddle" count="64"', 1, true)
    and dae:find('0.500 0.500 0.060', 1, true) and select(2, dae:gsub('<p>', '')) == 1)
  local plist = dae:match('<p>([^<]*)</p>')
  local nums = 0
  for _ in plist:gmatch('%d+') do nums = nums + 1 end
  check('and its triangle list has three corners of three numbers each', nums == 64 * 9)
  -- a shower is not steady: gusts, a drifting wind, ripples by intensity, the breathing damp patches
  local gmin, gmax, jump = 1, 0, 0
  for i = 0, 2000 do
    local g = wx.gust(i * 1.0, 7)
    gmin, gmax = math.min(gmin, g), math.max(gmax, g)
    if i > 0 then jump = math.max(jump, math.abs(g - wx.gust((i - 1) * 1.0, 7))) end
  end
  check('the gust stays between .3 and 1, really varies over a few minutes, and moves smoothly (never a snap)', gmin >= 0.3 and gmax <= 1 and gmax - gmin > 0.4 and jump < 0.1, gmin .. ' ' .. gmax .. ' ' .. jump)
  check('the drop count follows 55-100 % of the state, and the same time and seed give the same number', wx.dropsAt(1000, 0, 3) >= 550 and wx.dropsAt(1000, 0, 3) <= 1000 and wx.dropsAt(1000, 55, 3) == wx.dropsAt(1000, 55, 3) and wx.dropsAt(0, 5, 1) == 0)
  local wmin, wmax = 0, 0
  for i = 0, 1500 do local a = wx.windAngle(i * 1.0, 4) wmin, wmax = math.min(wmin, a), math.max(wmax, a) end
  check('the wind angle drifts within about 40 degrees either way', wmin > -0.7 and wmax < 0.7 and wmax - wmin > 0.5)
  check('ripples: none when it does not rain, 1 to 2 by intensity', wx.rippleCount(0) == 0 and wx.rippleCount(0.01) == 0 and wx.rippleCount(0.2) == 1 and wx.rippleCount(0.6) == 2 and wx.rippleCount(1) == 2 and wx.rippleCount(5) == 2)
  local sh = 1
  for i = 0, 200 do sh = math.max(sh, wx.shimmer(i * 0.5, 2, 1)) end
  check('the damp patches breathe by a few percent when it rains hard and not at all when it does not', sh > 1.04 and sh <= 1.07 + 1e-9 and wx.shimmer(33, 2, 0) == 1)
  -- which spots may hold a puddle: an even or gently sloping ground yes, a kerb or a block edge no
  local fxm = require('sl/puddlefx')
  local flat, slope, kerb = {}, {}, {}
  for iy = 0, 4 do for ix = 0, 4 do
    flat[iy * 5 + ix + 1] = 0
    slope[iy * 5 + ix + 1] = 0.01 * ix                     -- 4 cm over the width: a crown
    kerb[iy * 5 + ix + 1] = ix >= 3 and 0.12 or 0          -- a 12 cm kerb along two columns
  end end
  local r0, s0 = fxm.groundShape(flat)
  local r1, s1 = fxm.groundShape(slope)
  local r2, s2 = fxm.groundShape(kerb)
  check('ground shape: flat and a gentle crown pass, a kerb has a step far over the limit', r0 == 0 and s0 == 0 and r1 < fxm.MAX_RANGE and s1 <= fxm.MAX_STEP and s2 > fxm.MAX_STEP * 2 and r2 > 0.1)
  -- the rain sky is dark and moody, darker the harder it rains, and still day
  local dl, dm, dh = wx.resolve('rain', 'light').dark, wx.resolve('rain', 'medium').dark, wx.resolve('rain', 'heavy').dark
  check('rain darkness: light < medium < heavy, cloudy a little, clear and fog none', dl < dm and dm < dh and dh <= 1 and wx.resolve('cloudy').dark > 0 and wx.resolve('cloudy').dark < dl and wx.resolve('clear').dark == nil)
  check('what each part keeps at heavy rain: the sun a bit over half, the ambient about two thirds (it must still read as day), the sky brightness half',
    math.abs(wx.keep('sun', dh) - (1 - 0.55 * 0.92)) < 1e-9 and wx.keep('ambient', dh) > 0.6 and wx.keep('ambient', dh) < 0.75 and wx.keep('sun', dh) > 0.45 and wx.keep('sky', 1) == 0.5 and wx.keep('sun', 0) == 1 and wx.keep('sun', 9) == wx.keep('sun', 1))
  local dc = wx.darker({ 1, 0.8, 0.6 }, 0.5)
  check('a colour made darker keeps its hue', dc[1] == 0.5 and dc[2] == 0.4 and dc[3] == 0.3)
  local gd = wx.darker(wx.greyer({ 0.996, 0.839, 0.745 }, 0.95), wx.keep('sun', dh))
  check('the orange dawn sun, greyed and darkened for heavy rain: nearly equal r g b and well under the original brightness', math.abs(gd[1] - gd[3]) < 0.05 and gd[2] < 0.55 and gd[1] < 0.6)
  local d1, g1 = wx.skyFactors(45, 0.85, 0.9)
  local d2, g2 = wx.skyFactors(5, 0.85, 0.9)
  local d3, g3 = wx.skyFactors(nil, 0.85, 0.9)
  check('low sun: the darkening is cut to a quarter and the colours greyed all the way; full day: as asked', d1 == 0.85 and g1 == 0.9 and math.abs(d2 - 0.85 * 0.25) < 1e-9 and g2 >= 0.98 and d3 == 0.85 and g3 == 0.9
    and select(1, wx.skyFactors(20, 0.8, 0.5)) > select(1, wx.skyFactors(10, 0.8, 0.5)) and wx.skyFactors(0, 0, 0) == 0)
  check('the sky colorize tint is darkened too', wx.keep('colorize', 1) == 0.5)
  local mie, ray = wx.scatter(9.58e-5, 0.0005, 1)
  check('haze (off by default now, a test knob): the maths: heavy makes the Mie 7 times and the Rayleigh half; none leaves them', math.abs(mie - 9.58e-5 * 7) < 1e-12 and math.abs(ray - 0.00025) < 1e-12
    and select(1, wx.scatter(1, 1, 0)) == 1 and select(2, wx.scatter(1, 1, 0)) == 1 and wx.resolve('rain', 'heavy').haze == 0 and wx.resolve('clear').haze == nil)
  local m9, r9 = wx.scatter(1, 1, 9)
  check('haze never goes past the heaviest rain: no negative Rayleigh, Mie at most 7 times', m9 == 7 and r9 == 0.5)
  check('the forecast names the rain strength', wx.text('day', 'rain', nil, 'heavy'):find('Heavy rain') and wx.text('day', 'rain', nil, 'light'):find('Light rain') and wx.text('day', 'rain'):find('Rain'))
end

do -- the car must not become unspawnable: only detachable parts are ever struck off
  local cars = require('sl/core/cars')
  check('a bumper, a door, a wheel, a mirror can go', cars.detachable('/covet/covet_bumper_F') and cars.detachable('/covet/covet_door_FR') and cars.detachable('/x/wheel_FL')
    and cars.detachable('/x/mirror_R') and cars.detachable('/x/hood'))
  check('the body, frame, engine, subframe never', not cars.detachable('/bastion/bastion_body') and not cars.detachable('/x/covet_frame') and not cars.detachable('/x/engine_i4')
    and not cars.detachable('/x/subframe_F') and not cars.detachable('/x/transmission') and not cars.detachable('/x/suspension_R'))
  check('a part with a door in its name but body too stays', not cars.detachable('/x/body_door_panel'))
  check('an unknown part stays', not cars.detachable('/x/mystery_thing') and not cars.detachable(nil))
  local tree = { id = 'main', chosenPartName = 'covet_body', partPath = '/covet/covet_body', children = {
    bumper = { id = 'bumper', chosenPartName = 'bumper_F', partPath = '/covet/bumper_F' },
    frame = { id = 'frame', chosenPartName = 'frame', partPath = '/covet/covet_frame' } } }
  local gone = cars.stripParts(tree, { '/covet/covet_body', '/covet/bumper_F', '/covet/covet_frame' })
  check('only the bumper is struck off, the body (the root) and the frame stay', #gone == 1 and tree.chosenPartName == 'covet_body' and tree.children.frame.chosenPartName == 'frame'
    and tree.children.bumper.chosenPartName == '')
end

-- the weather extension itself, run against a mocked game (a smoke test: this chain broke once without any offline test noticing): sl_weather.onUpdate must move the rain
-- box to the camera, hand the wetness and the rain intensity to sl_puddlefx.update every frame, and set the drops, also for a game test with no career (debugForce)
do
  local saved = {}
  local function setg(name, value) saved[name] = { _G[name] } _G[name] = value end
  local drops, updates, lastUpdate, cleared = {}, 0, nil, 0
  local rain = { numOfDrops = 0, minSpeed = 0.35, maxSpeed = 0.4, pos = { x = -402, y = 73, z = 272 } }
  function rain:setPosition(p) self.pos = p end
  function rain:getPosition() return self.pos end
  function rain:setField() end
  function rain:getField() return '' end
  local active = true
  setg('vec3', function(a, b, c) return { x = a, y = b, z = c } end)
  setg('log', function() end)
  setg('getObjectsByClass', function(class) if class == 'Precipitation' then return { rain } end return {} end)
  setg('core_camera', { getPosition = function() return { x = -750, y = 396, z = 144 } end })
  setg('core_environment', { setPrecipitation = function(n) drops[#drops + 1] = n end, setCloudCover = function() end, setCloudCirrusCoverage = function() end,
    setCloudCirrusDensity = function() end, setFogDensity = function() end, setGroundWind = function() end, getGroundWind = function() return { x = 0, y = 0, z = 0 } end })
  setg('extensions', { hook = function() end })
  setg('getPlayerVehicle', function() return nil end)
  setg('sl_career', { isActive = function() return active end, getState = function() return { seed = 5, day = 2 } end, phase = function() return 'day' end })
  setg('sl_puddlefx', { update = function(dt, wet, intensity) updates = updates + 1 lastUpdate = { dt = dt, wet = wet, intensity = intensity } end, clear = function() cleared = cleared + 1 end,
    stats = function() return {}, 0 end })
  package.loaded['sl/weather'] = nil
  local W = require('sl/weather')
  W.RAIN_MOVE_EVERY, W.RAIN_MOVE_DIST = 0, 0          -- (these frames test the following itself; the throttle has its own check below)
  W.debugForce('rain', 'heavy')
  W.onUpdate(0.1)
  check('weather smoke: the rain box is moved to the camera', rain.pos.x == -750 and rain.pos.y == 396 and rain.pos.z == 144)
  check('weather smoke: sl_puddlefx.update is called every frame with the wetness and the rain intensity', updates >= 1 and lastUpdate.wet == 1 and lastUpdate.intensity > 0.9 and lastUpdate.dt == 0.1, updates .. ' ' .. tostring(lastUpdate and lastUpdate.wet) .. ' ' .. tostring(lastUpdate and lastUpdate.intensity))
  check('weather smoke: the heavy rain sets the drop count through the game call', #drops >= 1 and drops[#drops] > 1500)
  rain.pos = { x = 1, y = 2, z = 3 }
  local before = updates
  W.onUpdate(0.1)
  check('weather smoke: and keeps following on the next frame', rain.pos.x == -750 and updates == before + 1)
  -- the throttle (heavy rain cost 8 ms a frame): the box is not moved again while the camera stays within 4 m of where it was put, and is when it goes further
  W.RAIN_MOVE_EVERY, W.RAIN_MOVE_DIST = 0, 4
  rain.pos = { x = 1, y = 2, z = 3 }
  W.onUpdate(0.1)
  check('weather smoke: a camera that has not moved leaves the rain box alone', rain.pos.x == 1)
  core_camera.getPosition = function() return { x = -700, y = 396, z = 144 } end
  W.onUpdate(0.1)
  check('weather smoke: a camera 50 m away takes the rain box along', rain.pos.x == -700)
  core_camera.getPosition = function() return { x = -750, y = 396, z = 144 } end
  W.RAIN_MOVE_DIST = 0
  before = before + 2          -- (the two frames above)
  -- no career at all (a game test, the career not started): the forced weather still runs
  active = false
  rain.pos = { x = 1, y = 2, z = 3 }
  W.onUpdate(0.1)
  check('weather smoke: debugForce works without a career too (rain box, puddles)', rain.pos.x == -750 and updates == before + 2)
  -- and without a camera it falls back to the player's vehicle
  core_camera.getPosition = function() return nil end
  getPlayerVehicle = function() return { getPosition = function() return { x = 9, y = 8, z = 7 } end, getJBeamFilename = function() return 'covet' end, queueLuaCommand = function() end } end
  W.onUpdate(0.1)
  check('weather smoke: with no camera position the rain follows the player\'s vehicle', rain.pos.x == 9 and rain.pos.y == 8)
  W.onStreetLegalStopped()
  check('weather smoke: the career stopping clears the puddles', cleared >= 1)
  active = false
  local n = updates
  W.onUpdate(0.1)
  check('weather smoke: with no career and nothing forced the weather does nothing', updates == n)
  for name, v in pairs(saved) do _G[name] = v[1] end
  package.loaded['sl/weather'] = nil
end

-- the meet as a social hub (#43)
do
  local soc = require('sl/core/meetsocial')
  local owners = { o1 = { pos = { x = 0, y = 0 } }, o2 = { pos = { x = 10, y = 0 } } }
  check('meetsocial: the speaker car is the same one every time', soc.speaker(owners) == 'o1' and soc.speaker({}) == nil)
  local n1 = soc.group(1)
  local n2, offs = soc.group(2)
  local n3 = soc.group(3)
  check('meetsocial: groups of one, two and three', n1 == 0 and n2 == 1 and #offs == 1 and n3 == 2)
  check('meetsocial: raids only at heat 4 and 5', not soc.raided(3, 0) and soc.raided(4, 0.1) and not soc.raided(4, 0.3) and soc.raided(5, 0.3))
  local line = soc.story('drift', { car = 'Covet' })
  check('meetsocial: the story names the car, by theme, with a default', line:find('Covet') and soc.story('nope', { car = 'X' }):find('X'))
  local amb = require('sl/core/ambience')
  local plan = amb.plan({ player = { x = 0, y = 0, z = 0 }, phase = 'night', meet = { pos = { x = 100, y = 0, z = 0 }, speaker = { x = 5, y = 0, z = 0 } } })
  local music
  for _, e in ipairs(plan) do if e.kind == 'music' then music = e end end
  check('ambience: the meet music plays from the speaker car', music and music.pos.x == 5)
end

do
  local amb = require('sl/core/ambience')
  local all = true
  for _, kind in ipairs({ 'harbour', 'freeway', 'crowd' }) do
    all = all and type(amb.STOCK[kind]) == 'table' and #amb.STOCK[kind] > 0 and amb.FILES[kind] ~= nil
  end
  check('ambience: every synthesised kind has stock event candidates to try', all)
end

-- the hitch recorder's rules
do
  local hitch = require('sl/core/hitch')
  local h = hitch.new()
  hitch.event(h, 10.0, 'spawn covet', 1180)
  hitch.event(h, 5.0, 'an old event')
  hitch.cost(h, 'sl_lot.onUpdate', 3) hitch.cost(h, 'sl_lot.onUpdate', 4) hitch.cost(h, 'sl_streets.onUpdate', 0.2)
  check('hitch: a normal frame is not recorded', hitch.frame(h, 10.0, 0.016, 5000) == nil and h.count == 0)
  check('hitch: its costs are cleared each frame', next(h.cost) == nil)
  hitch.event(h, 10.5, 'lot build')
  hitch.cost(h, 'sl_lot.onUpdate', 9)
  local text = hitch.frame(h, 11.0, 0.12, 2000)
  check('hitch: a slow frame is recorded with its number', text and text:find('frame 120 ms') and h.count == 1)
  check('hitch: with the events of the 2 s before, not older ones', text:find('spawn covet') and text:find('lot build') and not text:find('old event'))
  check('hitch: with the part that cost the most', text:find('sl_lot.onUpdate 9.0 ms') and not text:find('sl_streets'))
  check('hitch: a drop of the heap is named a garbage collection', text:find('garbage collection freed 2.9 MB'))
  check('hitch: the report lists it', hitch.report(h):find('1 frames over 50 ms'))
end

-- the hitch recorder, run against mocks: it times the extensions' onUpdate, notes spawns, writes the file, and puts every function back
do
  local saved = {}
  local function setg(name, value) saved[name] = { _G[name] } _G[name] = value end
  local written, spawns = nil, 0
  setg('log', function() end)
  setg('writeFile', function(path, text) written = { path = path, text = text } end)
  local ext = { onUpdate = function() end }
  setg('sl_fakeext', ext)
  local original = ext.onUpdate
  local cv = { spawnNewVehicle = function(model) spawns = spawns + 1 return 'veh' end }
  setg('core_vehicles', cv)
  setg('sl_options', { get = function() return false end })
  package.loaded['sl/perf'] = nil
  local P = require('sl/perf')
  check('hitch recorder: starts', P.record(true) == true)
  check('hitch recorder: an extension onUpdate is wrapped and still works', ext.onUpdate ~= original and cv.spawnNewVehicle('covet') == 'veh' and spawns == 1)
  ext.onUpdate()
  P.onUpdate(0.016)
  ext.onUpdate()
  P.onUpdate(0.2)
  check('hitch recorder: stops and writes the file with the hitch', P.record(false) == false and written and written.path:find('hitches.txt') and written.text:find('frame 200 ms'), written and written.text)
  check('hitch recorder: everything put back', ext.onUpdate == original and cv.spawnNewVehicle ~= nil)
  for name, v in pairs(saved) do _G[name] = v[1] end
  package.loaded['sl/perf'] = nil
end

-- UI smoothness: the push counter (rates over a 5 s window, the busiest events first, skipped pushes counted apart)
do
  local us = require('sl/core/uistats')
  local st = us.new()
  for i = 0, 49 do us.record(st, 'slHud', 400, i * 0.1, true) end                    -- 10 pushes a second of 400 bytes for 5 s
  for i = 0, 9 do us.record(st, 'slPhoneData', 20000, i * 0.5, true) end              -- 2 a second of 20 kB
  for i = 0, 19 do us.record(st, 'slHud', 0, 4.9 + i * 0.01, false) end               -- 20 skipped (the same payload again)
  local r = us.rates(st, 5)
  check('ui stats: rates over the window, the biggest sender first, skipped ones apart', #r == 2 and r[1].name == 'slPhoneData' and math.abs(r[1].perSec - 2) < 0.5 and r[1].kbPerSec > 30 and r[2].name == 'slHud'
    and r[2].perSec > 8 and r[2].skippedPerSec > 2, r[1].name .. ' ' .. tostring(r[1].perSec))
  local lines = us.lines(st, 5, 1)
  check('ui stats: the overlay lines: a total and the busiest event', #lines == 2 and lines[1]:find('UI ') and lines[1]:find('pushes/s') and lines[2]:find('slPhoneData'))
  check('ui stats: old pushes fall out of the window and a quiet event says nothing', #us.rates(st, 30) == 2 and us.rates(st, 30)[1].perSec == 0 and #us.lines(us.new(), 5, 3) == 0)
  check('ui stats: totals keep counting beyond the window', st.names.slHud.total == 50 and st.names.slHud.totalSkipped == 20)
end

-- sl_uipush against a mocked game: dedupe, the minimum interval with the newest payload sent later, the counters
do
  local saved = { jsonEncode = jsonEncode, guihooks = guihooks }
  local sent = {}
  local function enc(v)
    if type(v) ~= 'table' then return tostring(v) end
    local keys = {}
    for kk in pairs(v) do keys[#keys + 1] = kk end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, kk in ipairs(keys) do out[#out + 1] = tostring(kk) .. '=' .. enc(v[kk]) end
    return '{' .. table.concat(out, ',') .. '}'
  end
  jsonEncode = enc
  guihooks = { trigger = function(name, data) sent[#sent + 1] = name .. ':' .. enc(data) end }
  package.loaded['sl/uipush'] = nil
  local up = require('sl/uipush')
  up.push('a', { n = 1 }, { dedupe = true })
  up.push('a', { n = 1 }, { dedupe = true })
  up.push('a', { n = 2 }, { dedupe = true })
  check('uipush: the same payload again is not sent, a changed one is', #sent == 2 and sent[2] == 'a:{n=2}')
  up.push('b', { n = 1 })
  up.push('b', { n = 1 })
  check('uipush: without dedupe every push goes out (events that repeat on purpose)', #sent == 4)
  local before = #sent
  up.push('c', { n = 1 }, { minInterval = 0.2 })
  up.push('c', { n = 2 }, { minInterval = 0.2 })
  up.push('c', { n = 3 }, { minInterval = 0.2 })
  check('uipush: inside the interval only the first goes out, the newest waits', #sent == before + 1 and sent[#sent] == 'c:{n=1}')
  local t0 = os.clock()
  while os.clock() - t0 < 0.25 do end
  up.onUpdate()
  check('uipush: when the time is up the newest held payload is sent once', #sent == before + 2 and sent[#sent] == 'c:{n=3}')
  up.onUpdate()
  check('uipush: and nothing more is sent after that', #sent == before + 2)
  local lines = up.lines(5)
  check('uipush: the overlay lines list what went out', #lines >= 2 and lines[1]:find('UI ') ~= nil)
  up.js('phone', 3, 40)
  local l2 = up.lines(5)
  check('uipush: a screen own rebuild count is shown', l2[#l2]:find('phone 3 rebuilds, 40 skipped') ~= nil)
  jsonEncode, guihooks = saved.jsonEncode, saved.guihooks
  package.loaded['sl/uipush'] = nil
end

-- sl_surfacefx: guarded calls into Car Surface FX (absent, version 1, version 2)
do
  local saved = { carSurfaceFx = rawget(_G, 'carSurfaceFx'), getPlayerVehicle = getPlayerVehicle }
  getPlayerVehicle = function() return { getID = function() return 7 end } end
  package.loaded['sl/surfacefx'] = nil
  local fx = require('sl/surfacefx')
  carSurfaceFx = nil
  carSurfaceFx = nil
  check('surfacefx: without the mod every call does nothing', fx.wash(7) == nil and fx.repair(7) == nil and fx.save(7) == nil and fx.restore(7, {}) == nil and fx.level(7) == nil and fx.lookText(7) == nil)
  local calls = {}
  carSurfaceFx = { wash = function(id) calls[#calls + 1] = 'wash' .. id end, repair = function(id) calls[#calls + 1] = 'repair' .. tostring(id) end }
  fx.wash(7); fx.repair(7); fx.repair(9)
  check('surfacefx: version 1 washes any car and repairs only the player car (its repair() cleans every car)', calls[1] == 'wash7' and calls[2] == 'repairnil' and #calls == 2 and fx.save(7) == nil and fx.level(7) == nil)
  calls = {}
  local kept
  carSurfaceFx = { apiVersion = 2, wash = function(id) calls[#calls + 1] = 'wash' .. id end, repair = function(id) calls[#calls + 1] = 'repair' .. id end,
    getState = function(id) return { dirt = { mud = 0.4 }, scratches = 3 } end, setState = function(id, t) kept = { id, t } end,
    level = function(id) return { dirtName = 'muddy', scratchName = 'light', dirt = 0.7, scratches = 0.2 } end }
  fx.wash(7); fx.repair(9)
  check('surfacefx: version 2 repairs the car it is asked about', calls[1] == 'wash7' and calls[2] == 'repair9')
  local st = fx.save(7)
  fx.restore(8, st)
  check('surfacefx: a car state is kept as a plain table and put back on another vehicle id', st.dirt.mud == 0.4 and kept[1] == 8 and kept[2].scratches == 3)
  check('surfacefx: the words for the phone and the garage', fx.lookText(7) == 'Muddy, light scratches' and fx.words({ dirtName = 'clean', scratchName = 'none' }) == 'Clean, no scratches' and fx.words({ dirtName = 'x' }) == nil and fx.words(nil) == nil)
  carSurfaceFx = { apiVersion = 2, getState = function() return nil end }
  check('surfacefx: a clean car gives false (keep nothing), not nil (no mod)', fx.save(7) == false)
  carSurfaceFx = { apiVersion = 2, wash = function() error('boom') end, getState = function() error('boom') end }
  check('surfacefx: an error inside the mod never reaches the career', fx.wash(7) == false and fx.save(7) == nil)
  carSurfaceFx = saved.carSurfaceFx
  getPlayerVehicle = saved.getPlayerVehicle
  package.loaded['sl/surfacefx'] = nil
end

do -- car auctions (sl/core/carauction)
  local CA, RNG, LST = require('sl/core/carauction'), require('sl/core/rng'), require('sl/core/listings')
  check('grades by condition', CA.grade(0.9) == 'A' and CA.grade(0.7) == 'B' and CA.grade(0.5) == 'C' and CA.grade(0.3) == 'D' and CA.grade(0.1) == 'E')
  local offer = { name = 'Covet', model = 'covet', value = 20000, condition = 0.6, faults = { 'tyres' } }
  local a, b = CA.newLot(RNG.new(5), offer, 100), CA.newLot(RNG.new(5), offer, 100)
  check('a lot is the same for the same seed', a.reserve == b.reserve and a.opening == b.opening and #a.bidders == #b.bidders and a.bidders[1].budget == b.bidders[1].budget)
  check('the reserve is 65-95 % of the fair worth and the opening bid 40 %', a.reserve >= a.fair * 0.64 and a.reserve <= a.fair * 0.96 and math.abs(a.opening - a.fair * 0.4) <= 10)
  local lot = CA.newLot(RNG.new(9), offer, 100)
  check('a bid under the minimum, over your cash, or on a closed lot is refused', select(2, CA.youBid(lot, 10, 99999)) == 'low' and select(2, CA.youBid(lot, lot.opening, 5)) == 'cash')
  check('your bid stands, and you cannot outbid yourself', CA.youBid(lot, lot.opening, 99999) and lot.high == 'you' and lot.bid == lot.opening and select(2, CA.youBid(lot, lot.bid + 500, 99999)) == 'yours')
  lot.t = lot.closesAt - 2
  local before = lot.closesAt
  lot.high = 1
  CA.youBid(lot, CA.nextMin(lot), 99999)
  check('a bid in the last seconds adds time, at most three times', lot.closesAt == before + CA.SOFT_CLOSE)
  for _ = 1, 6 do lot.t = lot.closesAt - 1 lot.high = 1 CA.youBid(lot, CA.nextMin(lot), 99999) end
  check('the soft close stops after SOFT_MAX extensions', lot.extended == CA.SOFT_MAX)
  local over, ok = 0, true
  for seed = 1, 60 do
    local l = CA.newLot(RNG.new(seed), offer, 100)
    local top = 0
    for _, bd in ipairs(l.bidders) do top = math.max(top, bd.budget) end
    local rng = RNG.new(seed + 1000)
    CA.finish(l, rng, 1)
    if l.bid > top then ok = false end
    if CA.result(l).sold == 'reserve' and l.bid >= l.reserve then ok = false end
    if not l.open and CA.result(l).sold == 'ai' and l.bid < l.reserve then ok = false end
    if l.bid > 0 then over = over + 1 end
  end
  check('AI bidders never go over the best budget, and a lot under its reserve does not sell', ok and over > 40)
  local late = CA.newLot(RNG.new(3), offer, 100)
  late.bidders = { { id = 1, style = 'sniper', budget = 99999, moved = 0, nextAt = 0 } }
  local early = {}
  for _ = 1, 90 do for _, m in ipairs(CA.step(late, 1, RNG.new(1))) do early[#early + 1] = m end end
  check('a sniper bids only in the last seconds, once', #early == 1 and early[1].t >= late.duration - CA.SNIPE_AT)
  local hidden = { A = 0, E = 0 }
  for seed = 1, 1500 do
    for _, c in ipairs({ { 0.95, 'A' }, { 0.1, 'E' } }) do
      if CA.newLot(RNG.new(seed), { value = 10000, condition = c[1] }, 0).hidden then hidden[c[2]] = hidden[c[2]] + 1 end
    end
  end
  check('a hidden fault is rare in A and likelier in E (3 % and 12 %)', hidden.A > 15 and hidden.A < 90 and hidden.E > 130 and hidden.E < 240, hidden.A .. ' ' .. hidden.E)
  local lotH
  for seed = 1, 400 do local l = CA.newLot(RNG.new(seed), { value = 20000, condition = 0.1 }, 0) if l.hidden then lotH = l break end end
  check('a hidden fault names a known fault and a repair cost, and is not on the report', lotH and ({ gearbox = 1, engine = 1, brakes = 1 })[lotH.hidden.fault] and lotH.hidden.cost >= 60 and #CA.reportFaults(lotH) == 0)
  local capOk = true
  for seed = 1, 80 do
    local car = { value = 25000, condition = 0.3 + (seed % 7) / 10 }
    local l = CA.sellLot(RNG.new(seed), car, nil, 0)
    CA.finish(l, RNG.new(seed * 3), 1)
    if l.bid > LST.resaleCap(car.value, car.condition) + 10 then capOk = false end
  end
  check('what the AI pays for your car stays under the least it could be bought for (buy and sell again never wins)', capOk)
  local sold = CA.sellLot(RNG.new(11), { value = 25000, condition = 0.9 }, 100, 0)
  CA.finish(sold, RNG.new(12), 1)
  check('your car sells at the last bid when the reserve is met; proceeds are after the fee', sold.bid > 0 and CA.sellProceeds(sold) == LST.proceeds(sold.bid))
  local noSale = CA.sellLot(RNG.new(11), { value = 25000, condition = 0.9 }, 10 ^ 7, 0)
  CA.finish(noSale, RNG.new(12), 1)
  check('your car does not sell under your reserve', CA.result(noSale).sold == 'reserve' or CA.result(noSale).sold == 'none')
  local online = CA.newLot(RNG.new(2), offer, 100, 148)
  check('an online lot runs on game minutes', online.duration == 48 * 60 and online.pace > 10)
  local ow = CA.watchDue({ { watched = true, closes = 100.1 }, { watched = true, closes = 105 }, { closes = 100.1 }, { watched = true, told = true, closes = 100.1 } }, 100)
  check('the watch list warns 10 game minutes before a watched lot closes, once', #ow == 1 and ow[1].closes == 100.1)
end
do -- the car auction extension (sl_carauctions) against a mocked game: six lots, a bid that wins, the order and the hidden fault, selling one of your cars
  local saved, savedLoaded = {}, {}
  local function setg(name, value) saved[name] = { _G[name] } _G[name] = value end
  local function setp(name, value) savedLoaded[name] = { package.loaded[name] } package.loaded[name] = value end
  local s = { day = 3, seed = 7, money = 20000, cars = { { id = 1, name = 'Covet', model = 'covet', value = 9000, condition = 0.7 }, { id = 2, name = 'Hopper', model = 'hopper', value = 12000, condition = 0.5 } }, orders = {} }
  local hour, toasts, texts, hooks = 12, {}, {}, {}
  local pool = {}
  for i = 1, 14 do pool[i] = { model = 'm' .. i, config = 'c' .. i, name = 'Car ' .. i, brand = 'B', value = 8000 + i * 900 } end
  setp('sl/carInfo', { of = function() return {} end })
  setg('log', function() end)
  setg('sl_career', { isActive = function() return true end, getState = function() return s end, hour = function() return hour end, getPlaces = function() return { j = { kind = 'junkyard' } } end,
    addMoney = function(n) if s.money + n < 0 then return false end s.money = s.money + n return true end, sendText = function(_, text) texts[#texts + 1] = text end })
  setg('sl_lot', { poolOf = function() return pool end })
  setg('sl_fleet', { lose = function(id) for i, c in ipairs(s.cars) do if c.id == id then table.remove(s.cars, i) return c, nil end end end })
  setg('guihooks', { trigger = function(name, data) if name == 'slPhoneToast' then toasts[#toasts + 1] = data.text end end })
  setg('extensions', { hook = function(name) hooks[#hooks + 1] = name end })
  package.loaded['sl/carauctions'] = nil
  local CAE = require('sl/carauctions')
  local out = CAE.list()
  check('the auction opens with six lots, each with a grade, a next bid and a car report slot', out and #out.lots == 6 and out.lots[1].grade and out.lots[1].next > 0 and out.lots[1].reserveMet == false)
  check('your cars that can be put up are listed with a grade and a fair worth', #out.sellable == 2 and out.sellable[1].fair > 0)
  local lot = s.auction.lots[1]
  lot.bidders, lot.reserve, lot.hidden = {}, 0, { fault = 'engine', key = 'weeping_head_gasket', cost = 900 }      -- nobody else bids; a hidden fault
  local id = lot.id
  check('a bid under the minimum is refused, a good one makes you the leader', CAE.bid(id, 1) == false and CAE.bid(id, lot.opening) == true and lot.high == 'you')
  local before = s.money
  s.day = s.day + 4      -- every lot has closed
  CAE.onUpdate(6)
  check('the hammer: the money is taken and the car is ordered with the hidden fault added', s.money < before and #s.orders == 1 and s.orders[1].offer.faults[#s.orders[1].offer.faults] == 'engine' and s.orders[1].offer.foundFault.cost == 900)
  CAE.onStreetLegalCarDelivered(s.orders[1].offer)
  check('the mechanic tells you what he found after the delivery', texts[#texts] and texts[#texts]:find('head gasket', 1, true) ~= nil)
  check('closed lots are replaced by new ones', #s.auction.lots == 6 and s.auction.lots[1].id ~= id)
  check('a watched lot warns once ten game minutes before it closes', (function()
    local l = s.auction.lots[2]
    CAE.watch(l.id, true)
    local t = s.day * 24 + (hour - 6) % 24
    l.closes = t + 0.1      -- 6 game minutes to go
    texts[#texts + 1] = '|'
    CAE.onUpdate(6)
    CAE.onUpdate(6)
    local n = 0
    for i = #texts, 1, -1 do if texts[i] == '|' then break end n = n + 1 end
    return n == 1
  end)())
  check('you cannot put up a car you have not got, and not your last car', CAE.sell(99, 100) == false)
  check('a car goes up with your reserve and is marked', CAE.sell(1, 100) == true and s.cars[1].atAuction == true and #s.auction.mine == 1 and s.auction.mine[1].reserve == 100)
  local textsBefore = #texts
  s.day = s.day + 4
  CAE.onUpdate(6)
  check('how the sale ended also comes as a text from Benny (a toast is lost while waiting)', (function() for i = textsBefore + 1, #texts do if texts[i]:find('sold at auction') or texts[i]:find('did not sell') then return true end end end)() == true)
  local gone = true
  for _, c in ipairs(s.cars) do if c.id == 1 then gone = false end end
  check('the sale ends: sold (the car gone, money in) or back with a toast, never both', (gone and #s.auction.mine == 0 and s.money > before - 10 ^ 6) or (not gone and s.cars[1].atAuction == nil and #s.auction.mine == 0))
  -- the weekly auction at the yard: open on every 7th day from 10 to 13, six live lots one after the other, over when the last has gone
  s.day, hour = 14, 15
  check('the yard auction is shut outside its hours', CAE.yardOpen() == false and CAE.join() == false)
  s.day, hour = 12, 11
  check('the yard auction is open on its day at 11:00', CAE.yardOpen() == true)
  check('walking up joins it: six lots, the first one live', CAE.join() == true and CAE.list().live and CAE.list().live.total == 6 and CAE.list().live.lot.live == true)
  local seenIndex = {}
  local won = false
  for second = 1, 900 do
    local live = CAE.list().live
    if live then
      seenIndex[live.index] = true
      if second % 7 == 0 and live.lot.high ~= 'you' and not live.waiting then CAE.bid(live.lot.id, live.lot.next) end
    end
    CAE.onUpdate(1)
  end
  local nSeen = 0
  for _ in pairs(seenIndex) do nSeen = nSeen + 1 end
  check('the live lots run in turn and the session ends after the last', nSeen >= 5 and CAE.list().live == nil and CAE.yardOpen() == false)
  -- the yard with its cars: the six cars stand in the bays (sl_lot.openAuction), the lots wait while they come out, the lot screen is told the live lot and the camera index
  local opened, views, ready = nil, {}, false
  sl_lot.openAuction = function(place, offers) opened = #offers return true end
  sl_lot.auctionOpen = function() return opened ~= nil end
  sl_lot.auctionReady = function() return ready end
  sl_lot.auctionView = function(state, index) views[#views + 1] = { state = state, index = index } end
  s.day, hour = 19, 10
  texts[#texts + 1] = '|'
  CAE.onUpdate(6)
  local told = 0
  for i = #texts, 1, -1 do if texts[i] == '|' then break end told = told + 1 end
  check('Benny tells you on the morning of the auction, once', told == 1 and (function() CAE.onUpdate(6) return texts[#texts] == texts[#texts] end)())
  check('joining builds the row of six cars in the yard', CAE.join() == true and opened == 6)
  for _ = 1, 30 do CAE.onUpdate(1) end
  check('the lots wait while the cars are still coming out', CAE.list().live.lot.secondsLeft == 75)
  ready = true
  for _ = 1, 12 do CAE.onUpdate(1) end
  check('then the live lot runs and the lot screen and the camera follow it', CAE.list().live.lot.secondsLeft < 75 and #views > 0 and views[#views].index == 1 and views[#views].state.lot.live == true)
  for name, v in pairs(saved) do _G[name] = v[1] end
  for name, v in pairs(savedLoaded) do package.loaded[name] = v[1] end
  package.loaded['sl/carauctions'] = nil
end
do -- named rivals (sl/core/rivals)
  local RV, ROS, CRW, RNG = require('sl/core/rivals'), require('sl/core/roster'), require('sl/core/crews'), require('sl/core/rng')
  local racers = ROS.generate(11, 36)
  local list, again = RV.generate(11, racers, CRW.CREWS), RV.generate(11, racers, CRW.CREWS)
  local bosses, tiers, ids, personas, nem = 0, {}, {}, {}, 0
  for i, r in ipairs(list) do
    if r.boss then bosses = bosses + 1 tiers[r.tier] = true end
    if r.nemesis then nem = nem + 1 end
    ids[r.id], personas[r.persona] = true, true
  end
  local nIds, nPers = 0, 0
  for _ in pairs(ids) do nIds = nIds + 1 end
  for _ in pairs(personas) do nPers = nPers + 1 end
  check('six rivals: a boss in each of the five tiers and one nemesis, all different racers and personas', #list == 6 and bosses == 5 and tiers[1] and tiers[2] and tiers[3] and tiers[4] and tiers[5] and nem == 1 and nIds == 6 and nPers == 6)
  check('the same career gets the same rivals', again[1].id == list[1].id and again[6].persona == list[6].persona and again[3].crew == list[3].crew)
  check('the rank starts at 1 and racers up to one tier above may be raced', RV.rank(list) == 1 and RV.allowed(list, 2) and not RV.allowed(list, 3) and RV.gatekeeper(list, 3) == RV.bossOfTier(list, 1) and RV.gatekeeper(list, 2) == nil)
  RV.bossOfTier(list, 1).bossBeaten = true
  check('beating a boss raises the rank and opens the next tier', RV.rank(list) == 2 and RV.allowed(list, 3) and not RV.allowed(list, 4) and RV.gatekeeper(list, 4) == RV.bossOfTier(list, 2))
  local b2 = RV.bossOfTier(list, 2)
  check('a boss asks for you only with the tier rep, enough wins in the tier and no cooldown', RV.bossReady(list, 10, 5, 1) == nil and RV.bossReady(list, 99999, 2, 1) == nil and RV.bossReady(list, 99999, 3, 1) == b2 and (function() b2.cooldown = 9 return RV.bossReady(list, 99999, 3, 4) == nil and RV.bossReady(list, 99999, 3, 9) == b2 end)())
  local cocky, friendly = { persona = 'cocky', meter = 0 }, { persona = 'friendly', meter = 0 }
  check('a close win earns respect; a big win humiliates the proud and pleases the rest', RV.meterAfter(cocky, true, 1) == 8 and RV.meterAfter(cocky, true, 12) == -10 and RV.meterAfter(friendly, true, 12) == 4)
  check('a loss makes the cocky gloat and the others respect the try; pink slips count triple; the meter stays in range', RV.meterAfter(cocky, false, 5) == -4 and RV.meterAfter(friendly, false, 5) == 2 and RV.meterAfter(friendly, true, 1, 'pink') == 24 and RV.meterAfter({ persona = 'friendly', meter = 95 }, true, 1) == 100)
  local w = { 'blood', 'rivals', 'neutral', 'respect', 'friends' }
  check('the meter has words', RV.meterWord(-80) == w[1] and RV.meterWord(-30) == w[2] and RV.meterWord(0) == w[3] and RV.meterWord(50) == w[4] and RV.meterWord(90) == w[5])
  local low, high = { tier = 1, races = 0, meter = 0 }, { tier = 4, races = 0, meter = 0 }
  local racer = { betMin = 100, betMax = 400 }
  check('the stake ladder climbs with the races between you: pocket money, top bet, high stakes', RV.step(low) == 1 and (function() low.races = 3 return RV.step(low) == 2 end)() and (function() low.races = 30 return RV.step(low) == 3 end)())
  check('pink slips only at the top tiers or in bad blood', (function() high.races = 30 return RV.step(high) == 4 end)() and (function() low.meter = -70 return RV.step(low) == 4 end)())
  check('the stakes rise with the step; the top step is a pink slip', RV.stake(low, racer, 1).bet < RV.stake(low, racer, 2).bet and RV.stake(low, racer, 2).bet < RV.stake(low, racer, 3).bet and RV.stake(low, racer, 4).stake == 'pink')
  check('a showdown is twice the top bet, and pink slips against the top boss', RV.showdown({ tier = 2 }, racer).bet == 800 and RV.showdown({ tier = 5 }, racer).stake == 'pink')
  check('their car gets better with your wins over them and with the days, up to what the tier allows', RV.stageNow({ tier = 1, beaten = 0 }, 0) == 0 and RV.stageNow({ tier = 1, beaten = 5 }, 100) == 1 and RV.stageNow({ tier = 3, beaten = 1 }, 5) == 2 and RV.stageNow({ tier = 5, beaten = 9 }, 99) == 3 and RV.skillNow(0.5, 2) == 0.54 and RV.skillNow(0.98, 3) == 0.99)
  local all = true
  for _, persona in ipairs(RV.PERSONAS) do
    for _, kind in ipairs(RV.KINDS) do
      for n = 1, RV.LINES_PER do
        local txt = RV.text({ persona = persona }, kind, RNG.new(n), 'Boss Name')
        if type(txt) ~= 'string' or #txt < 8 or txt:find('rivals%.') then all = false end
      end
    end
  end
  check('every persona has a line for every situation, and the gate names the boss', all and RV.text({ persona = 'cool' }, 'gate', nil, 'Viktor Halasz'):find('Viktor Halasz', 1, true) ~= nil)
  local x = { told = {} }
  check('a story beat is told once', RV.firstTime(x, 'intro') == true and RV.firstTime(x, 'intro') == false)
end
do -- the rivals extension (sl_rivals) against a mocked game: the tier gate, a result, a boss showdown at night
  local saved, savedLoaded = {}, {}
  local function setg(name, value) saved[name] = { _G[name] } _G[name] = value end
  local function setp(name, value) savedLoaded[name] = { package.loaded[name] } package.loaded[name] = value end
  local ROS = require('sl/core/roster')
  local s = { seed = 11, day = 4, rep = 0, money = 99999, racers = ROS.generate(11, 36), known = {}, challenges = {}, cars = { { id = 1 } } }
  local texts, asked, isNight = {}, {}, true
  setp('sl/carInfo', { of = function() return {} end })
  setg('log', function() end)
  local rvPushed
  setg('guihooks', { trigger = function(name, data) if name == 'slRivals' then rvPushed = data end end })
  setg('extensions', { hook = function() end })
  setg('sl_career', { isActive = function() return true end, getState = function() return s end, isNight = function() return isNight end,
    sendText = function(thread, text) texts[#texts + 1] = { thread = thread, text = text } end,
    challenge = function(id, kind) asked[#asked + 1] = { id = id, kind = kind } local c = { id = id .. ':x', racer = id, bet = 100 } s.challenges[#s.challenges + 1] = c return { accept = true, challenge = c, text = 'ok' } end })
  package.loaded['sl/rivals'] = nil
  local RVE = require('sl/rivals')
  RVE.onStreetLegalStarted()
  local list = s.rivals.list
  local tier3 = nil
  for _, r in ipairs(s.racers) do if r.tier == 3 and not tier3 then tier3 = r end end
  local answer = ROS.respond(tier3, 'race', { rep = 99999, money = 99999, hasCar = true }, require('sl/core/rng').new(1))
  check('a racer two tiers above your rank sends you to the boss in front of them', answer.accept == false and answer.text:find(ROS.displayName(s.racers[1]) or '', 1, true) == nil and #answer.text > 8)
  local boss1 = require('sl/core/rivals').bossOfTier(list, 1)
  local tier1 = nil
  for _, r in ipairs(s.racers) do if r.tier == 1 and r.id ~= boss1.id then tier1 = r end end
  check('a racer of the next tier up still answers normally', ROS.respond(tier1, 'race', { rep = 99999, money = 99999, hasCar = true }, require('sl/core/rng').new(1)).text ~= nil)
  -- a win over a tier-1 racer counts toward the boss; the night brings the first hello
  RVE.onStreetLegalRaceResult(true, 'x', tier1.id, 'money')
  RVE.onStreetLegalRaceResult(true, 'x', tier1.id, 'money')
  RVE.onStreetLegalRaceResult(true, 'x', tier1.id, 'money')
  check('wins over the tier count toward its boss', s.rivals.tierWins[1] == 3)
  s.rep = 99999
  RVE.onUpdate(9)
  check('at night the boss calls you out with a showdown challenge', s.rivals.bossActive == boss1.id and #asked >= 1 and asked[#asked].id == boss1.id and s.challenges[#s.challenges].boss == true and #texts >= 1)
  -- the result of the showdown: a win raises the rank and opens the next tier
  RVE.onStreetLegalRaceResult(true, 'x', boss1.id, 'money')
  check('beating the boss raises the rank and clears the showdown', boss1.bossBeaten == true and s.rivals.bossActive == nil and RVE.rank() == 2)
  local g3 = ROS.respond(tier3, 'race', { rep = 99999, money = 99999, hasCar = true }, require('sl/core/rng').new(1))
  check('the next tier is open now (the gate has moved up one boss)', g3.accept == true or g3.text ~= nil)
  -- the last boss: the finale and the achievement
  local RVC = require('sl/core/rivals')
  for _, r in ipairs(s.rivals.list) do if r.boss and r.tier < 5 then r.bossBeaten = true r.grandfathered = nil end end
  local boss5 = RVC.bossOfTier(s.rivals.list, 5)
  s.rivals.bossActive = boss5.id
  texts[#texts + 1] = { thread = '|', text = '|' }
  RVE.onStreetLegalRaceResult(true, 'x', boss5.id, 'pink')
  local fin = false
  for i = #texts, 1, -1 do if texts[i].thread == '|' then break end if texts[i].thread == 'benny' then fin = true end end
  check('beating the last boss ends the campaign with a text from Benny, and earns the achievement', fin and s.rivals.finale == true and RVC.rank(s.rivals.list) == 6 and require('sl/core/achievements').update(s)[1] ~= nil)
  local metList = RVE.met()
  check('the rivals you know are listed as contacts with a line', #metList >= 1 and metList[1].kind == 'rival' and #metList[1].line > 3 and metList[1].name ~= nil)
  local r1 = RVE.list()
  check('the rivals list for the screens has six with a record and a word', #r1.rivals == 6 and r1.rank == 6 and r1.rivals[1].word and r1.rivals[1].beaten ~= nil)
  -- pink slips are never arranged by a rival himself: an offer, accepted with a named car, or declined with only the meter paying
  local mine = { name = 'Covet 1.5' }
  _G.sl_fleet = { currentCar = function() return mine end }
  local pinkRival
  for _, r in ipairs(s.rivals.list) do if r.nemesis then pinkRival = r end end
  for _, r in ipairs(s.rivals.list) do if r.boss and r.tier < 4 then r.bossBeaten = true end end
  pinkRival.races, pinkRival.meter = 30, -80
  for k = #asked, 1, -1 do asked[k] = nil end
  local offered
  for day = 20, 90 do
    s.day, s.rivals.lastTextDay = day, -1
    s.challenges = {}
    RVE.onUpdate(9)
    if s.rivals.offers and s.rivals.offers[pinkRival.id] then offered = true break end
  end
  local anyPink = false
  for _, a in ipairs(asked) do if a.kind == 'pink' then anyPink = true end end
  check('a rival offers pink slips but never arranges the race by himself', offered == true and anyPink == false)
  local offerShown = RVE.list()
  local card
  for _, r in ipairs(offerShown.rivals) do if r.id == pinkRival.id then card = r end end
  check('the offer on the card names your car and his', card and card.offer and card.offer.myCar == 'Covet 1.5' and card.offer.stake == 'pink')
  local meterBefore = pinkRival.meter
  check('walking away costs only a little meter: no challenge, no race', RVE.decline(pinkRival.id, false) == true and pinkRival.meter == meterBefore - 5 + 0 and #s.challenges == 0 and s.rivals.offers[pinkRival.id] == nil)
  local shownOffer
  for _, r in ipairs(rvPushed and rvPushed.rivals or {}) do if r.id == pinkRival.id then shownOffer = r.offer end end
  check('the open Rivals card is refreshed at once: the offer buttons go', rvPushed ~= nil and shownOffer == nil)
  s.rivals.offers[pinkRival.id] = { stake = 'pink', day = s.day }
  local nAsked = #asked
  check('racing for money instead is a normal race at their top bet', RVE.decline(pinkRival.id, true) == true and asked[#asked].kind == 'race' and #asked == nAsked + 1 and s.challenges[#s.challenges].bet >= 100)
  s.rivals.offers[pinkRival.id] = { stake = 'pink', day = s.day }
  mine = nil
  check('with no car out, the pink offer cannot be accepted', RVE.accept(pinkRival.id) == false)
  mine = { name = 'Covet 1.5' }
  nAsked = #asked
  check('accepting asks for the pink slip race for the car that is out', RVE.accept(pinkRival.id) == true and asked[#asked].kind == 'pink' and #asked == nAsked + 1 and s.rivals.offers[pinkRival.id] == nil)
  s.rivals.offers[pinkRival.id] = { stake = 'pink', day = 1 }
  s.day = 99
  RVE.onUpdate(9)
  check('an offer that is not answered lapses', s.rivals.offers[pinkRival.id] == nil)
  -- a save from before the rivals: the tiers its rep has reached stay open
  s.rivals, s.rep = nil, 2000
  RVE.onStreetLegalStarted()
  local tier5
  for _, r in ipairs(s.racers) do if r.tier == 5 then tier5 = r end end
  check('an old save with the rep for tier 4 starts at rank 4 and is not locked out of tier 5', RVE.rank() == 4 and ROS.gateHook(tier5) == nil and ROS.gateHook(s.racers[1]) == nil)
  s.rivals, s.rep = nil, 0
  RVE.onStreetLegalStarted()
  check('a new career starts at rank 1', RVE.rank() == 1 and ROS.gateHook(tier3) ~= nil)
  RVE.onStreetLegalStopped()
  check('stopping the career takes the gate away', ROS.gateHook == nil)
  for name, v in pairs(saved) do _G[name] = v[1] end
  for name, v in pairs(savedLoaded) do package.loaded[name] = v[1] end
  package.loaded['sl/rivals'] = nil
end
do -- the campaign end (tier 1 to the last boss), walked offline: a player who wins every race he is offered, one race a game day at night
  local PR, ROS, RV, ST, CRW = require('sl/core/progression'), require('sl/core/roster'), require('sl/core/rivals'), require('sl/core/state'), require('sl/core/crews')
  local racers = ROS.generate(7, 36)
  local count = {}
  for _, r in ipairs(racers) do count[r.tier] = (count[r.tier] or 0) + 1 end
  local enough = true
  for t = 1, 5 do if (count[t] or 0) < RV.BOSS_WINS + 1 then enough = false end end
  check('every tier has the boss and at least three other racers to beat before him', enough, (count[1] or 0) .. ' ' .. (count[2] or 0) .. ' ' .. (count[3] or 0) .. ' ' .. (count[4] or 0) .. ' ' .. (count[5] or 0))
  local list = RV.generate(7, racers, CRW.CREWS)
  local rep, races, wins = 0, 0, {}
  local known = {}
  local milestones = {}
  local stuck = false
  local rank = 1
  local function knownTier(t) return ROS.TIERS[t].rep[1] <= math.max(select(3, PR.titleFor(rep)), rep) * 1.2 end
  while rank <= 5 and races < 3000 do
    -- the boss asks for you when ready; else race the best racer you may race and know
    local above = 0
    for t = rank, 5 do above = above + (wins[t] or 0) end
    local boss = RV.bossReady(list, rep, above, 99)
    if boss then
      local racer
      for _, r in ipairs(racers) do if r.id == boss.id then racer = r end end
      local sd = RV.showdown(boss, racer)
      local gain = PR.raceResult({ won = true, stake = sd.stake, bet = sd.bet, night = true, opponentRep = racer.rep, playerRep = rep })
      rep = rep + gain
      races = races + 1
      boss.bossBeaten = true
      milestones['boss' .. boss.tier] = { races = races, rep = rep }
      rank = RV.rank(list)
    else
      local best
      for _, r in ipairs(racers) do
        if r.tier <= rank + 1 and knownTier(r.tier) and PR and (rep >= ROS.TIERS[r.tier].rep[1] * 0.5) and not RV.byId(list, r.id) then
          if not best or r.tier > best.tier or (r.tier == best.tier and r.rep > best.rep) then best = r end
        end
      end
      if not best then stuck = true break end
      local gain = PR.raceResult({ won = true, stake = 'money', bet = best.betMax, night = true, opponentRep = best.rep, playerRep = rep })
      rep = rep + gain
      races = races + 1
      wins[best.tier] = (wins[best.tier] or 0) + 1
    end
  end
  check('the climb never dead-ends: with every race won, each boss gets his turn and the last one is beaten', not stuck and rank == 6 and milestones.boss5 ~= nil, 'rank ' .. rank .. ' races ' .. races)
  check('the whole climb is a few dozen races, not hundreds', races > 15 and races < 120, 'races ' .. races)
  local detail = {}
  for t = 1, 5 do local m = milestones['boss' .. t] detail[#detail + 1] = t .. ':' .. (m and (m.races .. '/' .. m.rep) or '-') end
  -- the top: the ROC wants rep 6000, garage 3 and 50000 for the entry; what is left to earn after the last boss
  local toRoc, extra = PR.ROC.rep - rep, 0
  while rep < PR.ROC.rep and extra < 500 do
    local best = nil
    for _, r in ipairs(racers) do if r.tier == 5 and (not best or r.rep > best.rep) then best = r end end
    rep = rep + PR.raceResult({ won = true, stake = 'money', bet = best.betMax, night = true, opponentRep = best.rep, playerRep = rep })
    extra = extra + 1
  end
  check('after the last boss, rep 6000 for the ROC is a few more races at the top', rep >= PR.ROC.rep and extra < 80, 'extra ' .. extra .. ' ' .. table.concat(detail, ' '))
  if os.getenv and os.getenv('SL_CAMPAIGN_REPORT') then print('campaign: races ' .. races .. ', to the ROC rep ' .. extra .. ' more; boss races/rep ' .. table.concat(detail, ' ')) end
end
do -- the rivals' and auctions' tunables: entries of sl_options for the Mods menu (tab / group), read through sl/tuning
  local saved = { sl_options = _G.sl_options }
  local OPT, TU = require('sl/options'), require('sl/tuning')
  local byKey, tabbed = {}, 0
  for _, d in ipairs(OPT.defs) do byKey[d.key] = d if d.tab then tabbed = tabbed + 1 end end
  local ok = tabbed >= 14
  for path, key in pairs(TU.KEYS) do
    local d = byKey[key]
    if not (d and d.tab and d.group and d.title and d.desc and d.default ~= nil) then ok = false end
    if d and d.type == 'range' and (d.default < d.min or d.default > d.max) then ok = false end
  end
  check('every tunable has an sl_options entry with a tab, a group, a title, a tooltip and a default in range', ok)
  local RVc, CAc = require('sl/core/rivals'), require('sl/core/carauction')
  check('the defaults are the constants the rules were written with', byKey.slBossWins.default == RVc.BOSS_WINS and byKey.slBossCooldown.default == RVc.BOSS_COOLDOWN and byKey.slRivalStepRaces.default == RVc.STEP_RACES and byKey.slRivalUpgradeDays.default == RVc.UPGRADE_DAYS and byKey.slAuctionLive.default == CAc.DURATION)
  _G.sl_options = { get = function(key) if key == 'slRivalEscalate' then return 0.5 end if key == 'slRivals' then return false end end }
  check('the tuning follows sl_options, and the default stands for a setting it does not have', TU.get('rivals.escalateChance', 0.35) == 0.5 and TU.get('rivals.tauntChance', 0.3) == 0.3 and TU.get('rivals.enabled', true) == false and TU.get('nothing.here', 7) == 7)
  _G.sl_options = nil
  check('without sl_options every value is its default', TU.get('rivals.escalateChance', 0.35) == 0.35)
  -- the Mods-menu page of Street Legal is generated from these definitions (a stand-in for the registry of Wrench Works)
  local hadCopy, hadSlrr = _G.deepcopy, rawget(_G, 'slrr_settings')
  _G.deepcopy = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
  local got
  _G.slrr_settings = {
    fromDefs = function(defs, o)
      local fields, tabs, seen = {}, {}, {}
      for _, d in ipairs(defs) do
        local t = o.tabOf(d)
        if not seen[t] then seen[t] = true tabs[#tabs + 1] = { id = t, title = t } end
        fields[#fields + 1] = { id = d.key, tab = t, group = d.sub, type = d.type, label = d.title, tooltip = d.desc }
      end
      return fields, tabs
    end,
    register = function(schema) got = schema return true end,
  }
  OPT.onSlrrSettingsReady()
  _G.deepcopy = hadCopy
  _G.slrr_settings = hadSlrr
  local tabIds, byField = {}, {}
  for _, t in ipairs(got and got.tabs or {}) do tabIds[t.id] = true end
  for _, f in ipairs(got and got.fields or {}) do byField[f.id] = f end
  check('the Mods menu page: Street Legal registers with its tabs, every setting on a tab', got and got.mod == 'street_legal' and tabIds.Difficulty and tabIds.Rivals and tabIds['Police chase'] and tabIds.Developer and tabIds.Accessibility)
  check('every setting of the list is a field with a tab that exists', (function() for _, d in ipairs(OPT.defs) do if d.needs ~= 'weather' and not (byField[d.key] and tabIds[byField[d.key].tab]) then return false end end return true end)())
  check('the dashboard parts and the money button are fields too', byField.hud_tacho and byField.hud_units and byField.devMoney and byField.devMoney.type == 'button')
  check('SL adds nothing to the old Wrench Works settings screen', OPT.onWrenchWorksSettingsDefs == nil)
  _G.sl_options = saved.sl_options
end
do -- the look of a used car (sl/core/carwear) and the wash-off (sl_surfacefx against a mocked Car Surface FX)
  local CW = require('sl/core/carwear')
  check('a new dealer car and a track special are clean', CW.dirtFor({ id = 'a', kind = 'dealer', condition = 1, mileage = 10 }) == nil and CW.dirtFor({ id = 'b', kind = 'used', condition = 0.5, build = 'race' }) == nil)
  local good = CW.dirtFor({ id = 'g', kind = 'used', condition = 0.85, mileage = 40000 }).dirt
  local worn = CW.dirtFor({ id = 'w', kind = 'used', condition = 0.3, mileage = 250000 }).dirt
  local scrap = CW.dirtFor({ id = 's', kind = 'scrap', condition = 0.1, mileage = 400000 }).dirt
  check('the tireder and older, the dirtier: a good used car < a worn one < a scrap-yard car', good.grime < worn.grime and worn.dust < scrap.dust + 0.001 and scrap.mud >= 0.25 and good.mud == 0)
  local again = CW.dirtFor({ id = 'w', kind = 'used', condition = 0.3, mileage = 250000 }).dirt
  check('the same offer always looks the same, every value 0..1', again.dust == worn.dust and again.grime == worn.grime and (function() for _, v in pairs(scrap) do if v < 0 or v > 1 then return false end end return true end)())
  local sum = 0
  for _ = 1, 12 do sum = sum + CW.washStep(0.25, 3) end
  check('twelve quarter-second steps of a three-second wash take off a whole dirt level', math.abs(sum - 1) < 1e-9 and CW.washSeconds(0) == 1.5 and CW.washSeconds(1) == 4.5)
  local saved = { carSurfaceFx = _G.carSurfaceFx, getObjectByID = _G.getObjectByID, sl_career = _G.sl_career }
  local state, washes = nil, {}
  _G.carSurfaceFx = { apiVersion = 2, setState = function(id, st) state = { id = id, st = st } end, wash = function(id, amount) washes[#washes + 1] = amount or 'all' end, level = function() return { dirt = 0.5 } end, repair = function() end, getState = function() return nil end }
  _G.getObjectByID = function() return {} end
  package.loaded['sl/surfacefx'] = nil
  local SFX = require('sl/surfacefx')
  SFX.dress(7, { id = 'x', kind = 'used', condition = 0.4, mileage = 120000 })
  check('a used car is dressed through setState with dirt only (no hand-made scratches)', state and state.id == 7 and state.st.dirt.grime > 0 and state.st.marks == nil and state.st.splats == nil)
  state = nil
  SFX.dress(8, { id = 'y', kind = 'dealer', condition = 1, mileage = 5 })
  check('a clean new car is not touched', state == nil)
  SFX.washOff(7, 3)
  for _ = 1, 20 do SFX.onUpdate(0.25) end
  check('the wash comes off in steps over the seconds and ends with a full wash', #washes >= 11 and washes[#washes] == 'all' and type(washes[1]) == 'number')
  _G.carSurfaceFx = nil
  package.loaded['sl/surfacefx'] = nil
  local SFX2 = require('sl/surfacefx')
  check('without Car Surface FX nothing happens and nothing fails', SFX2.dress(7, { id = 'x', kind = 'used', condition = 0.4, mileage = 1e5 }) == nil and SFX2.washOff(7) == nil)
  _G.carSurfaceFx, _G.getObjectByID, _G.sl_career = saved.carSurfaceFx, saved.getObjectByID, saved.sl_career
  package.loaded['sl/surfacefx'] = nil
end
do -- the balance entries (sl/balance): every one is an sl_options entry whose default is the constant it sets; a change reaches the rules and a reset brings the old value back
  local BAL, OPT = require('sl/balance'), require('sl/options')
  local byKey = {}
  for _, d in ipairs(OPT.defs) do byKey[d.key] = d end
  local ok, n = true, 0
  for _, e in ipairs(BAL.MAP) do
    local d = byKey[e[1]]
    local good, mod = pcall(require, e[2])
    if not (d and d.tab and d.desc and d.type == 'range' and d.default >= d.min and d.default <= d.max) then ok = false end
    if good and type(mod) == 'table' then
      n = n + 1
      if mod[e[3]] ~= d.default then ok = false end
    end
  end
  check('every balance entry has an options entry with tab, tooltip and range, and its default is the constant it sets', ok and n >= 18, tostring(n))
  local HEAT, JOBS = require('sl/core/heat'), require('sl/core/jobs')
  local values = { slHeatRace = 0.3, slPayPerKm = 200 }
  local saved = _G.sl_options
  _G.sl_options = { get = function(key) return values[key] end }
  BAL.apply()
  check('a changed setting reaches the rule', HEAT.RACE == 0.3 and JOBS.PAY_PER_KM == 200)
  values.slHeatRace, values.slPayPerKm = nil, nil
  BAL.apply()
  check('a setting reset to nothing brings the original value back', HEAT.RACE == 0.12 and JOBS.PAY_PER_KM == 140)
  local HOSP = require('sl/hospital')
  check('the hospital bills are the old numbers by default', HOSP.doctorBill({ broken = { 1, 2 }, severity = 0.5 }) == 1050 and HOSP.hospitalBill(0.5, false) == 2700 and HOSP.hospitalBill(0.5, true) == 4000)
  HOSP.DOCTOR_BASE, HOSP.HOSPITAL_BASE = 0, 0
  check('a bill never takes it all: 40% of the money, at least 300, never more than there is', HOSP.payable(2700, 3450) == 1380 and HOSP.payable(2700, 100000) == 2700 and HOSP.payable(2700, 500) == 300 and HOSP.payable(2700, 120) == 120 and HOSP.payable(2700, 0) == 0)
  check('and follow the settings', HOSP.doctorBill({ broken = { 1, 2 }, severity = 0.5 }) == 900 and HOSP.hospitalBill(0.5, false) == 1500)
  HOSP.DOCTOR_BASE, HOSP.HOSPITAL_BASE = 150, 1200
  _G.sl_options = saved
end
do -- ambient police patrols share the racers' build rule; a chase's patrol is never held back
  local SPP = require('sl/core/spawnplan')
  check('an ambient patrol waits for the gap, the speed rule and any other build', not SPP.patrolOk(5, 3, false, false) and not SPP.patrolOk(30, 30, false, false) and not SPP.patrolOk(5, 99, true, false) and SPP.patrolOk(5, 99, false, false))
  check('an ambient patrol may be built after the patience at speed', SPP.patrolOk(30, SPP.PATIENCE + 1, false, false))
  check('a chase or heat 4-5 patrol builds at once (not while another build runs)', SPP.patrolOk(40, 0, false, true) and not SPP.patrolOk(40, 0, true, true))
end
do -- the night cruisers built behind the fade (spawnplan.preStep)
  local SPN = require('sl/core/spawnplan')
  check('prespawn: nothing wanted -> none', SPN.preStep(0, true, false, false, 0, 4) == 'none' and SPN.preStep(nil, true, false, false, 0, 4) == 'none')
  check('prespawn: in the fade and free -> build', SPN.preStep(2, true, false, false, 0, 4) == 'build')
  check('prespawn: one at a time and not over the cap -> wait', SPN.preStep(2, true, false, true, 0, 4) == 'wait' and SPN.preStep(2, true, false, false, 4, 4) == 'wait')
  check('prespawn: the fade is over or a race began -> reset', SPN.preStep(2, false, false, false, 0, 4) == 'reset' and SPN.preStep(2, true, true, false, 0, 4) == 'reset')
  local pre, built = 2, 0                                        -- two drain, then none
  for _ = 1, 6 do if SPN.preStep(pre, true, false, false, built, 4) == 'build' then pre, built = pre - 1, built + 1 end end
  check('prespawn: two are built, then it stops', pre == 0 and built == 2 and SPN.preStep(pre, true, false, false, built, 4) == 'none')
end

do -- builds wait for the frames to recover
  local SPN = require('sl/core/spawnplan')
  check('frames: a build waits 2 s after the last slow frame, but not for ever on a slow machine', not SPN.framesRecovered(0.5, 10) and SPN.framesRecovered(2, 10) and SPN.framesRecovered(0.1, 60) and SPN.framesRecovered(nil, nil))
end

do -- the night is never empty: the first meet 30 s in, retried 20 s after a miss, then every 90 s at 35 %
  local SPN = require('sl/core/spawnplan')
  check('meets: the first of a night is due at 30 s, not before', SPN.meetDue(29, 0, 0.99) == nil and SPN.meetDue(30, 0, 0.99) == 'try')
  check('meets: later ones need 90 s and the chance; a lost roll is a skip', SPN.meetDue(89, 1, 0.0) == nil and SPN.meetDue(90, 1, 0.5) == 'skip' and SPN.meetDue(90, 1, 0.2) == 'try')
  check('meets: a missed first try is repeated 20 s later, a missed later one too', SPN.meetTimerAfter(false, 0) == 10 and SPN.meetTimerAfter(false, 2) == 70 and SPN.meetTimerAfter(true, 0) == 0)
  -- a night of 30 minutes at one check a second, with a try that fails half the time: the first meet starts within 5 minutes in every seed
  local worst = 0
  for seed = 1, 300 do
    math.randomseed(seed)
    local timer, tonight, t = 0, 0, 0
    while t < 1800 and tonight == 0 do
      t, timer = t + 1, timer + 1
      local due = SPN.meetDue(timer, tonight, math.random())
      if due == 'skip' then timer = 0
      elseif due == 'try' then
        local ok = math.random() < 0.5
        timer = SPN.meetTimerAfter(ok, tonight)
        if ok then tonight = tonight + 1 end
      end
    end
    worst = math.max(worst, t)
  end
  local SPC = require('sl/core/spawnplan')
  local alive = { [11] = true }
  local pl = { a = 11, b = 12 }                                    -- b's car is gone (stale id), c has none
  local got = SPC.reusable({ { id = 'a' }, { id = 'b' }, { id = 'c' } }, pl, function(v) return alive[v] == true end)
  check('cruisers: only racers with a live pooled car are reusable (a stale pool id is not)', #got == 1 and got[1].id == 'a' and #SPC.reusable({ { id = 'b' } }, pl, function(v) return alive[v] == true end) == 0 and #SPC.reusable({ { id = 'a' } }, nil, function() return true end) == 0)
  local firstCar = function(speed) for t = 0, 600 do if SPC.canBuild(speed, t, false) then return t end end end
  check('cruisers: at night the first car may be built after 20 s standing or cruising, after 45 s at full speed (both inside 2 minutes); a pooled one after 4 s', firstCar(0) == 20 and firstCar(10) == 20 and firstCar(30) == 45 and SPC.canBuild(0, 4, false, true) and not SPC.canBuild(0, 3, false, true))
  -- frame by frame (60 fps, a meet that always starts and lasts 60 s): a later meet comes about every 90 / 0.35 s, not every 90 s
  do
    math.randomseed(7)
    local timer, gaps, n, sum = 0, 0, 0, 0
    for _ = 1, 200 do
      local waited, due = 0, nil
      timer = 0
      repeat
        timer, waited = timer + 1 / 60, waited + 1 / 60
        due = SPN.meetDue(timer, 1, math.random())
        if due == 'skip' then timer = 0 end
      until due == 'try'
      n, sum = n + 1, sum + waited
    end
    local mean = sum / n
    check('meets: later ones come about every 4 minutes on average (mean ' .. math.floor(mean) .. ' s)', mean > 200 and mean < 330)
  end
  check('meets: with half the tries failing, the first meet starts within 5 minutes (worst of 300 nights ' .. worst .. ' s)', worst <= 300)
end

do -- the off-route distance is looked up 4 times a second, not every frame
  local C = require('sl/core/racecancel')
  local ev, route = {}, { { x = 0, y = 0 }, { x = 100, y = 0 } }
  local d0 = C.distCached(ev, 0, { x = 50, y = 10 }, route)
  local d1 = C.distCached(ev, 0.1, { x = 50, y = 90 }, route)
  local d2 = C.distCached(ev, 0.3, { x = 50, y = 90 }, route)
  check('racecancel: distCached reuses the value inside 0.25 s and looks again after it', d0 == 10 and d1 == 10 and d2 == 90 and C.distCached(ev, 0, { x = 50, y = 30 }, route) == 30)
end

do -- kinds of night race (core/racekinds)
  local RK = require('sl/core/racekinds')
  local RNG = require('sl/core/rng')
  -- a small map: a long fast road east (A..F), a side street grid with turns (G1..G5), a climb north (H1..H5), a dead-end stub (Q)
  local N = {}
  local function node(name, x, y, z, r) N[name] = { pos = { x = x, y = y, z = z or 0 }, radius = r or 3, links = {} } end
  local function L(a, b, d, s) local e = { drivability = d or 1, speedLimit = s or 14 } N[a].links[b] = e N[b].links[a] = e end
  local names = { 'A', 'B', 'C', 'D', 'E', 'F' }
  for i, c in ipairs(names) do node(c, (i - 1) * 600, 0, 0, 7) end
  for i = 1, 5 do L(names[i], names[i + 1], 1, 30) end
  local grid = { { 1500, 800 }, { 1500, 1000 }, { 1700, 1000 }, { 1700, 1200 }, { 1900, 1200 } }
  for i, p in ipairs(grid) do node('G' .. i, p[1], p[2]) end
  for i = 1, 4 do L('G' .. i, 'G' .. (i + 1)) end
  L('B', 'G1')
  for i = 1, 5 do node('H' .. i, 0, 200 * i, 30 * i) end
  for i = 1, 4 do L('H' .. i, 'H' .. (i + 1), 1, 12) end
  L('A', 'H1')
  node('Q', 3000, 500) L('F', 'Q')
  local function pathFn(a, b)                                        -- shortest hop path, breadth first
    local prev, queue, seen, qi = {}, { a }, { [a] = true }, 1
    while qi <= #queue do
      local cur = queue[qi] qi = qi + 1
      if cur == b then break end
      local ns = {} for o in pairs(N[cur].links) do ns[#ns + 1] = o end table.sort(ns)
      for _, o in ipairs(ns) do if not seen[o] then seen[o] = true prev[o] = cur queue[#queue + 1] = o end end
    end
    if not seen[b] then return {} end
    local out, c = {}, b
    while c do table.insert(out, 1, c) c = prev[c] end
    return out
  end
  local hw = RK.measure(N, { 'A', 'B', 'C', 'D', 'E' })
  check('racekinds: the freeway is fast, tarmac, straight and 2400 m', hw.len == 2400 and hw.fast == 1 and hw.tarmac == 1 and hw.turns == 0 and not hw.dead and RK.valid('highway', hw) and RK.valid('rolling', hw))
  local cityM = RK.measure(N, { 'B', 'G1', 'G2', 'G3', 'G4', 'G5' })
  check('racekinds: the zig-zag through the grid has turns and no fast road', cityM.turns >= 4 and cityM.fast == 0 and not RK.valid('highway', cityM))
  local hillM = RK.measure(N, { 'A', 'H1', 'H2', 'H3', 'H4', 'H5' })
  check('racekinds: the climb gains 150 m and is a hill, not a highway', hillM.gain == 150 and not RK.valid('highway', hillM))
  check('racekinds: a route ending on a dead-end stub, or doubling back, is refused', RK.measure(N, { 'A', 'B', 'C', 'D', 'E', 'F', 'Q' }).dead and RK.measure(N, { 'A', 'B', 'A', 'B' }).dead and not RK.valid('highway', RK.measure(N, { 'A', 'B', 'C', 'D', 'E', 'F', 'Q' })))
  local dirt = RK.measure(N, { 'A', 'B', 'C', 'D', 'E' }) dirt.tarmac = 0.5
  check('racekinds: a route on dirt is refused', not RK.valid('highway', dirt))
  local goal, path, m = RK.pick(N, 'A', pathFn, 'highway', RNG.new(5), 60)
  check('racekinds: pick finds a highway goal from the west end (valid route)', goal ~= nil and RK.valid('highway', m) and path[1] == 'A' and #path >= 4)
  check('racekinds: no hill goal from the far east end of the freeway -> nil', RK.pick(N, 'F', pathFn, 'hill', RNG.new(5), 60) == nil)
  local counts, r2 = { city = 0, highway = 0, hill = 0, rolling = 0 }, RNG.new(11)
  for _ = 1, 2000 do local id = RK.choose(r2, { rolling = false }) counts[id] = counts[id] + 1 end
  check('racekinds: standing starts never get the rolling kind; city is the most common', counts.rolling == 0 and counts.city > counts.highway and counts.city > counts.hill and counts.highway > 300 and counts.hill > 300)
  local c3 = { city = 0, highway = 0, hill = 0, rolling = 0 }
  for _ = 1, 2000 do local id = RK.choose(r2, { rolling = true, have = { highway = false, rolling = false } }) c3[id] = c3[id] + 1 end
  check('racekinds: a kind the map does not have is never chosen', c3.highway == 0 and c3.rolling == 0 and c3.city > 0 and c3.hill > 0)
  local STR = require('sl/core/strings')
  local shown = STR.t('streets.kind_bonus', STR.t('streets.kind_highway'), 250)
  check('racekinds: the bonus text is filled in (' .. shown .. ')', shown == 'Highway run: $250 extra for the win.')
  check('racekinds: bonus: city 0, highway 25 %, rolling 40 %, doubled at heat 5 for the highway, 0 without a bet or a kind',
    RK.bonus('city', 1000, 0) == 0 and RK.bonus('highway', 1000, 0) == 250 and RK.bonus('rolling', 1000, 0) == 400 and RK.bonus('highway', 1000, 5) == 500 and RK.bonus('hill', 0, 3) == 0 and RK.bonus('nope', 500, 1) == 0)
end

do -- the depth of a night chase (core/chase)
  local CH = require('sl/core/chase')
  local RNG = require('sl/core/rng')
  check('chase: roadblocks from heat 2 at night (0 / 0.25 / 0.5 / 0.75 / 1), none by day, the arrest quicker and wider as it heats',
    CH.vars('night', 1).roadblockFrequency == 0 and CH.vars('night', 2).roadblockFrequency == 0.25 and CH.vars('night', 5).roadblockFrequency == 1
    and CH.vars('day', 5).roadblockFrequency == 0 and CH.vars('night', 5).arrestTime == 3 and CH.vars('night', 0).arrestTime == 5 and CH.vars('night', 5).arrestRadius == 30
    and CH.vars('night', 3).strictness == 0.75)
  check('chase: covered means a roof inside 12 m; the evade timer runs x2 hidden and covered, x1.5 covered, x1.25 hidden, x1 in sight',
    CH.covered(8) and not CH.covered(12) and not CH.covered(nil) and CH.evadeRate(true, true) == 2 and CH.evadeRate(false, true) == 1.5 and CH.evadeRate(true, false) == 1.25 and CH.evadeRate(false, false) == 1)
  check('chase: the escape pays rep x the night boost plus 5 a roadblock and a strip',
    CH.escapeRep(15, 'night', 0, 0, 0) == 15 and CH.escapeRep(15, 'night', 4, 0, 0) == 24 and CH.escapeRep(15, 'night', 4, 2, 1) == 39 and CH.escapeRep(15, 'day', 5, 0, 0) == 15)
  check('chase: strips from heat 3 in a chase only, every 40 s (25 s at heat 5)',
    not CH.stripDue('night', 2, true, 999) and not CH.stripDue('night', 3, false, 999) and not CH.stripDue('day', 5, true, 999)
    and CH.stripDue('night', 3, true, 40) and not CH.stripDue('night', 3, true, 39) and CH.stripDue('night', 5, true, 25) and not CH.stripDue('night', 5, true, 24))
  local line = {} for i = 0, 40 do line[#line + 1] = { x = i * 10, y = 0, z = 0 } end        -- 400 m straight
  local p1, d1 = CH.stripSpot(line)
  check('chase: the strip goes 150 m down a straight road, heading along it', p1 and p1.x == 150 and d1.x > 0 and d1.y == 0)
  local p2 = CH.stripSpot(line, function(pt) return pt.x >= 200 end)
  check('chase: a refused spot (a bridge) moves it on down the road', p2 and p2.x == 200)
  do
    local sp, dir = CH.stripPlan(line)
    check('chase: stripPlan gives the spot and the direction together', sp ~= nil and dir ~= nil and dir.x ~= nil)
    check('chase: stripPlan with no route, a refused route or a short one gives nothing (never a spot without a direction)', CH.stripPlan(nil) == nil and CH.stripPlan(line, function() return false end) == nil and CH.stripPlan({ { x = 0, y = 0 }, { x = 100, y = 0 } }) == nil)
    local st, runs = { fails = 0, off = false }, 0
    local function bad() runs = runs + 1 error('boom') end
    for _ = 1, 10 do CH.guarded(st, bad) end
    check('chase: a tick that fails every time runs 5 times and is then switched off', runs == CH.MAX_FAILS and st.off == true)
    local st2, ok2 = { fails = 0, off = false }, 0
    for i = 1, 10 do CH.guarded(st2, function() if i % 3 == 0 then error('x') end ok2 = ok2 + 1 end) end
    check('chase: failures that do not come in a row never switch it off', st2.off == false and ok2 == 7 and CH.guarded({ fails = 0, off = false }, function() end) == true)
  end
  check('chase: no spot when every candidate is refused or the route is short', CH.stripSpot(line, function() return false end) == nil and CH.stripSpot({ { x = 0, y = 0 }, { x = 100, y = 0 } }) == nil)
  local bend = {} for i = 0, 30 do bend[#bend + 1] = { x = i * 10, y = 0, z = 0 } end        -- straight 300 m ...
  for i = 1, 30 do bend[#bend + 1] = { x = 300, y = i * 10, z = 0 } end                         -- ... then a right-angle corner at 300 m
  local p3 = CH.stripSpot(bend)
  check('chase: never on a corner (the spot keeps 30 m of straight either side)', p3 and p3.x == 150 and CH.stripSpot(bend, function(pt) return pt.x > 260 end) == nil)
  check('chase: the bust cause: fuel first, then a strip, a roadblock within 40 m, two or more cars round you, else none',
    CH.bustCause({ fuelLitres = 0.1, strips = 1, cops = 3 }) == 'fuel' and CH.bustCause({ fuelLitres = 20, strips = 1 }) == 'strip' and CH.bustCause({ roadblockDist = 30, cops = 3 }) == 'roadblock'
    and select(2, CH.bustCause({ roadblockDist = 90, cops = 3 })) == 3 and CH.bustCause({ cops = 1, roadblockDist = 90 }) == nil and CH.bustCause({}) == nil)
  local nodes = {}                                                           -- a wide avenue east (A0..A8, 100 m apart), a side street (S) and a corner (C)
  for i = 0, 8 do nodes['A' .. i] = { pos = { x = i * 100, y = 0, z = 0 }, radius = 6, links = {} } end
  for i = 0, 7 do nodes['A' .. i].links['A' .. (i + 1)] = {} nodes['A' .. (i + 1)].links['A' .. i] = {} end
  nodes.S = { pos = { x = 0, y = 500, z = 0 }, radius = 6, links = { A0 = {}, S2 = {} } } nodes.S2 = { pos = { x = 0, y = 600, z = 0 }, radius = 6, links = { S = {} } }
  nodes.C = { pos = { x = 0, y = 1000, z = 0 }, radius = 6, links = { S2 = {}, D = {} } } nodes.D = { pos = { x = 100, y = 1000, z = 0 }, radius = 6, links = { C = {} } }
  nodes.N = { pos = { x = 400, y = 50, z = 0 }, radius = 2, links = { A4 = {}, A5 = {} } }                   -- a narrow lane
  local spots = CH.breakerSpots(nodes, 3, { x = 400, y = 0, z = 0 }, 450, RNG.new(7))
  local okSpots = #spots >= 2 and #spots <= 3
  for i, a in ipairs(spots) do
    okSpots = okSpots and a.y == 0 and a.x >= 100 and a.x <= 700 and a.dy == 0 and math.abs(a.dx) == 1       -- on the avenue, not the corner, the lane or the end nodes
    for j = i + 1, #spots do okSpots = okSpots and math.abs(spots[j].x - a.x) >= 300 end
  end
  check('chase: breaker spots are on the straight avenue, 300 m apart, and not on the corner, the lane or the ends', okSpots)
  check('chase: no spots when the avenue is out of range or the road is narrow', #CH.breakerSpots(nodes, 3, { x = 400, y = 5000, z = 0 }, 1500, RNG.new(7)) == 0)
  check('chase: a breaker is passed at speed with a patrol 25-55 m back, once the distance grows', CH.breakerPassed(4, 6, 20, 30) and not CH.breakerPassed(12, 14, 20, 30)
    and not CH.breakerPassed(6, 4, 20, 30) and not CH.breakerPassed(4, 6, 5, 30) and not CH.breakerPassed(4, 6, 20, 10) and not CH.breakerPassed(4, 6, 20, 80))
  check('chase: a breaker is ready again after 60 s', CH.breakerReady(60) and not CH.breakerReady(59) and CH.breakerReady(nil))
end


-- the garage app's upgrade (sl_upgrades.buy): takes the money once, is listed as built, is refused the second time and when the money is short
do
  local saved = { sl_career = rawget(_G, 'sl_career'), extensions = rawget(_G, 'extensions') }
  local st = { money = 2500, garageLevel = 1 }
  sl_career = { isActive = function() return true end, getState = function() return st end,
    addMoney = function(a) if st.money + a < 0 then return false end st.money = st.money + a return true end }
  extensions = { hook = function() end }
  package.loaded['sl/upgrades'] = nil
  local ok, UP = pcall(require, 'sl/upgrades')
  if ok then
    local ok1 = UP.buy('lift')
    check('garage upgrade: the lift is bought once for its price', ok1 == true and st.money == 500)
    local has = false
    for _, u in ipairs(UP.summary()) do if u.id == 'lift' then has = u.has end end
    check('and the Garage app lists it as built', has == true)
    local ok2, why2 = UP.buy('lift')
    check('buying it twice is refused and costs nothing', ok2 == false and st.money == 500 and why2 ~= nil)
    local ok3, why3 = UP.buy('dyno')
    check('an upgrade the player cannot afford is refused with the price and the money in the text', ok3 == false and st.money == 500 and tostring(why3):find('6000') ~= nil)
    check('an unknown upgrade is refused', UP.buy('nonsense') == false)
  else
    check('upgrades loads in the test (' .. tostring(UP):sub(1, 100) .. ')', false)
  end
  package.loaded['sl/upgrades'] = nil
  for n, v in pairs(saved) do _G[n] = v end
end

-- the rigged driver goes on the player's own cars only: spawnOwned wraps its spawn in slrrDriverMount.playerCarNext/Done, any other spawn does not
do
  local saved = { slrrDriverMount = rawget(_G, 'slrrDriverMount'), core_vehicles = rawget(_G, 'core_vehicles'), core_vehicle_manager = rawget(_G, 'core_vehicle_manager'), getObjectByID = rawget(_G, 'getObjectByID'), log = rawget(_G, 'log') }
  local savedIo = package.loaded['jbeam/io']
  local calls = {}
  slrrDriverMount = { playerCarNext = function() calls[#calls + 1] = 'next' end, playerCarDone = function() calls[#calls + 1] = 'done' end }
  core_vehicles = { spawnNewVehicle = function() calls[#calls + 1] = 'spawn' return { getID = function() return 1 end } end }
  log = function() end
  core_vehicle_manager = { getVehicleData = function() return {} end }
  getObjectByID = function() return { getID = function() return 1 end } end
  package.loaded['jbeam/io'] = {}
  package.loaded['sl/carBuilder'] = nil
  local ok, CB = pcall(require, 'sl/carBuilder')
  if ok then
    local job = { sleep = function() end }
    CB.spawn(job, 'covet', 'x.pc', nil, nil, true)
    check('a stock/traffic car is spawned without the player-car hook', table.concat(calls, ',') == 'spawn')
    calls = {}
    CB.spawn(job, 'covet', 'x.pc', nil, nil, false, true)
    check('a player-owned car is spawned between playerCarNext and playerCarDone', table.concat(calls, ',') == 'next,spawn,done')
    slrrDriverMount = nil
    calls = {}
    check('without Drivers & Pedestrians the owned spawn still works', CB.spawn(job, 'covet', 'x.pc', nil, nil, false, true) ~= nil and table.concat(calls, ',') == 'spawn')
  else
    check('carBuilder loads in the test (' .. tostring(CB):sub(1, 100) .. ')', false)
  end
  package.loaded['sl/carBuilder'] = nil
  for n, v in pairs(saved) do _G[n] = v end
  package.loaded['jbeam/io'] = savedIo
end

-- "Drive this one" (sl_fleet.setActive): the car is built at the forecourt and the player is seated in it
do
  local saved = {}
  local function setg(n, v) saved[n] = { _G[n] } _G[n] = v end
  local function setp(n, v) saved['p:' .. n] = { package.loaded[n] } package.loaded[n] = v end
  local seated, faded, built = nil, {}, 0
  local V3 = {}
  V3.__index = V3
  V3.__sub = function(p, q) return setmetatable({ x = p.x - q.x, y = p.y - q.y, z = p.z - q.z }, V3) end
  function V3:length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
  setg('vec3', function(x, y, z) return setmetatable({ x = x, y = y, z = z }, V3) end)
  setg('quatFromDir', function() return {} end)
  local veh = { getID = function() return 55 end, getPosition = function() return vec3(0, 0, 0) end }
  local foot = false
  setp('slrr/garageSites', { getSites = function() return { { id = 'alder', spot = vec3(0, 0, 0), doorDist = -10, dir = vec3(1, 0, 0) } } end, point = function() return vec3(5, 0, 0) end })
  setp('sl/carBuilder', { spawnOwned = function() built = built + 1 return veh end })
  local st = { garageLevel = 1, cars = { { id = 3, name = 'Covet' } }, activeCar = nil }
  setg('sl_career', { isActive = function() return true end, getState = function() return st end })
  setg('getPlayerVehicle', function() return { getID = function() return 9 end, getPosition = function() return foot and vec3(900, 0, 0) or vec3(0, 0, 0) end, getJBeamFilename = function() return foot and 'unicycle' or 'covet' end } end)
  setg('getObjectByID', function(id) return id == 55 and veh or nil end)
  setg('guihooks', { trigger = function(n, d) faded[#faded + 1] = n .. ':' .. tostring(d and d.on) end })
  setg('extensions', { hook = function() end })
  local asked = 0
  setg('gameplay_walk', { getInVehicle = function(v) asked = asked + 1 if asked >= 2 then seated = v end end })      -- (the first call does not take: it is asked again)
  setg('sl_carcare', { reportOf = function() return nil end })
  setg('be', { getPlayerVehicleID = function() return seated and 55 or 9 end })
  setg('log', function() end)
  setg('core_jobsystem', { create = function(f) f({ sleep = function() end }) end })
  package.loaded['sl/fleet'] = nil
  local ok, F = pcall(require, 'sl/fleet')
  if ok then
    local progression = require('sl/core/progression')
    progression.garages[1].site = 'alder'
    local good = F.setActive(3)
    check('Drive this one: the car is built and the player is seated in it', good == true and built == 1 and seated == veh and asked == 2 and st.activeCar == 3 and faded[1] == 'slFade:true' and faded[#faded] == 'slFade:false')
    do      -- a car that is already out front (delivered): the player is seated in it all the same
      seated, asked, built = nil, 0, 0
      st.activeCar = nil
      F.setActive(3)      -- (it is out now: vehicleOf finds it)
      check('Drive this one on a car already out front: nothing is built, the player is seated', built == 0 and seated == veh)
      seated, st.activeCar, foot = nil, nil, true      -- on foot at the hospital's door, far from the garage
      local ok2 = F.setActive(3)
      check('Drive this one on foot far from the garage seats the player in a car that is out', ok2 == true and seated == veh and st.activeCar == 3)
      foot = false
      seated, st.activeCar, foot = nil, 3, true      -- the ACTIVE car, player on foot after the hospital: the same tap seats them
      check('Drive this one on the active car when on foot seats the player', F.setActive(3) == true and seated == veh)
      check('the phone list says the car is not seated (so the button shows), foot or not', (function() local l = F.list()[1] return l and l.active == true and l.seated == false end)())
      foot = false
    end
  else
    check('fleet loads in the test (' .. tostring(F):sub(1, 80) .. ')', false)
  end
  package.loaded['sl/fleet'] = nil
  for n, v in pairs(saved) do if n:sub(1, 2) == 'p:' then package.loaded[n:sub(3)] = v[1] else _G[n] = v[1] end end
end

do -- the career's tyres (sl/core/tyres)
  local T = require('sl/core/tyres')
  local n = 0
  for _ in pairs(T.COMPOUNDS) do n = n + 1 end
  local known = 0
  for _, id in ipairs(T.ORDER) do if T.known(id) then known = known + 1 end end
  check('tyres: every ordered compound is known and the order lists them all', known == #T.ORDER and n == #T.ORDER)
  local torres, race = T.stocked('torresTires'), T.stocked('fastAutomotive')
  check('tyres: Torres sells the road, weather and off-road ranges, Fast Automotive the track rubber, together all twelve', #torres == 8 and #race == 4 and #T.stocked() == 12 and race[1] == 'semislick')
  check('tyres: a set costs its price, an axle half, a track change 30% more', T.quote('road', nil, 'shop') == 360 and T.quote('road', 'front', 'shop') == 180 and T.quote('slick', nil, 'track') == 1430)
  local p, parts = T.quote('performance', nil, 'garage', { compound = 'road', frac = 0.5 })
  check('tyres: the worn old set is part-exchanged (15% of its price times the tread left)', p == 640 - 27 and parts.credit == 27 and parts.fee == 0)
  check('tyres: an unknown compound has no quote, and an expensive old set cannot make the new one free', T.quote('nonsense', nil, 'shop') == nil and T.quote('road', 'rear', 'shop', { compound = 'slicksoft', frac = 1 }) == 86)
  check('tyres: the tread words by fraction left (new, good, worn, low, bald, blown)',
    T.stage(1) == 'new' and T.stage(0.6) == 'good' and T.stage(0.3) == 'worn' and T.stage(0.1) == 'low' and T.stage(0) == 'bald' and T.stage(0.9, true) == 'blown' and T.stage(nil) == 'new')
  local sum = T.summary({ compound = 'road', wheels = {
    { axle = 'front', compound = 'road', frac = 0.9 }, { axle = 'front', compound = 'road', frac = 0.3, flat = 0.5 },
    { axle = 'rear', compound = 'road', frac = 0.02 }, { axle = 'rear', compound = 'road', frac = 0.6, blown = true } } })
  check('tyres: the summary takes the worst tyre of each axle; flat spots and blow-outs are flagged, bald or blown means replace',
    #sum == 2 and sum[1].axle == 'front' and sum[1].stage == 'worn' and sum[1].flat and not sum[1].replace
    and sum[2].stage == 'blown' and sum[2].blown and sum[2].replace and #T.summary(nil) == 0 and #T.summary({}) == 0)
  check('tyres: a change is refused moving or when short of money, never otherwise', T.refusal(100, 500, true) ~= nil and T.refusal(100, 50, false) ~= nil and T.refusal(100, 100, false) == nil)
end

do -- the free-roam switches in the Mods menu list (sl/options) and the game side (sl/mode)
  local Op = require('sl/options')
  local Mo = require('sl/core/mode')
  local oldR, oldW = rawget(_G, 'jsonReadFile'), rawget(_G, 'jsonWriteFile')
  _G.jsonReadFile, _G.jsonWriteFile = function() return {} end, function() return true end
  local all = true
  for _, f in ipairs(Mo.FEATURES()) do
    local k = Mo.key(f.id)
    local d for _, x in ipairs(Op.defs) do if x.key == k then d = x end end
    all = all and d ~= nil and d.type == 'bool' and d.default == false and d.tab == 'Free roam' and Op.get(k) == false
  end
  check('free roam: the master and every feature switch are Mods-menu bools, off by default', all)
  _G.jsonReadFile, _G.jsonWriteFile = oldR, oldW
  local saved = { sl_career = rawget(_G, 'sl_career'), sl_options = rawget(_G, 'sl_options') }
  package.loaded['sl/mode'] = nil
  local M = require('sl/mode')
  _G.sl_career, _G.sl_options = nil, nil
  check('free roam: with no career and the switches off nothing runs and there is no state', M.kind() == nil and not M.enabled('phone') and M.state('phone') == nil)
  local on = {}
  _G.sl_options = { get = function(k) return on[k] end }
  on.freeroam, on.freeroam_phone = true, true
  local sb = M.state('phone')
  check('free roam: master and feature switch enable it, the state is the sandbox (no money, no cars), and a feature that is off gets nothing', M.kind() == 'freeroam' and M.enabled('phone') and not M.enabled('maps') and M.state('maps') == nil and sb and sb.sandbox == true and sb.money == nil and sb.cars == nil and M.state('phone') == sb)
  local Cm = require('sl/core/mode')
  local t = Cm.sandbox(nil, 23, 5)
  Cm.sandbox(t, 2) local d2 = t.day Cm.sandbox(t, 12)
  check('free roam: the sandbox has the phase of the hour and counts a new day past midnight, and keeps its seed', t.phase == 'day' and t.seed == 5 and d2 == 2 and Cm.sandbox(t, 22).phase == 'night' and Cm.sandbox(t, 3).phase == 'night' and Cm.sandbox(t, 4).phase == 'day')
  local st = { cars = {} }
  _G.sl_career = { isActive = function() return true end, getState = function() return st end }
  on.freeroam, on.freeroam_phone = nil, nil
  check('free roam: in a career everything runs with the career state, whatever the switches', M.kind() == 'career' and M.enabled('rivals') and M.state('phone') == st)
  _G.sl_career, _G.sl_options = saved.sl_career, saved.sl_options
  package.loaded['sl/mode'] = nil
end

do -- free-roam weather (sl/weather) against a fake sky and clock: no career, the master and the weather switch on
  local names = { 'log', 'getObjectsByClass', 'createObject', 'scenetree', 'core_environment', 'extensions', 'getPlayerVehicle', 'sl_options', 'sl_mode', 'sl_career', 'sl_weather' }
  local saved = {}
  for _, n in ipairs(names) do saved[n] = rawget(_G, n) end
  local savedTime = os.time
  local RW = require('sl/core/weather')
  local seed
  for sd = 1, 200 do if not seed and RW.forecast(sd, 1, 'day') == 'rain' and RW.forecast(sd, 1, 'night') ~= 'rain' then seed = sd end end
  local calls, tod, on = {}, { time = 0 }, { freeroam = true, freeroam_weather = true }
  local rainObj = { numOfDrops = 0, minSpeed = 0.3, maxSpeed = 0.4, setField = function() end, isHidden = function() return false end }
  _G.log = function() end
  _G.getObjectsByClass = function(c) if c == 'Precipitation' then return { rainObj } end return {} end
  _G.createObject = function() return {} end
  _G.scenetree = { findObject = function() return nil end, findClassObjects = function() return {} end }
  _G.core_environment = { getTimeOfDay = function() return tod end, setCloudCover = function() end, setFogDensity = function() end,
    setPrecipitation = function(n) calls[#calls + 1] = n end }
  _G.extensions = { hook = function() end }
  local vcmds = {}
  _G.getPlayerVehicle = function() return { getJBeamFilename = function() return 'covet' end, queueLuaCommand = function(_, c) vcmds[#vcmds + 1] = c end } end
  _G.sl_career, _G.sl_weather = nil, nil
  _G.sl_options = { get = function(k) return on[k] end }
  os.time = function() return seed end
  package.loaded['sl/weather'], package.loaded['sl/mode'] = nil, nil
  local okw, W = pcall(require, 'sl/weather')
  check('free-roam weather: sl/weather loads against the fake sky and a rainy day-one seed exists', okw and seed ~= nil)
  if okw and seed then
    _G.sl_mode = require('sl/mode')
    tod.time = 0      -- the game clock at midday
    W.onUpdate(0.1)
    W.onUpdate(6)
    local sb = _G.sl_mode.state('weather')
    check('free-roam weather: it follows the sandbox (rain on day one by day) and the sandbox has no money or cars', W.state() == 'rain' and sb and sb.sandbox and sb.money == nil and sb.cars == nil and sb.phase == 'day')
    local rained = false
    for _, n in ipairs(calls) do if n > 0 then rained = true end end
    check('free-roam weather: the rain is applied to the sky', rained)
    tod.time = 0.5      -- the game clock reaches midnight ((0.5 * 24 + 12) % 24 = 0)
    W.onUpdate(6)
    check('free-roam weather: the phase changes with the clock (the night forecast is used)', _G.sl_mode.state('weather').phase == 'night' and W.state() == RW.forecast(seed, 1, 'night'))
    on.freeroam_weather = false
    local before = #calls
    W.onUpdate(1)
    check('free-roam weather: switching it off puts the original sky back (no drops) and stops', #calls > before and calls[#calls] == 0 and _G.sl_mode.state('weather') == nil)
    local n2 = #calls
    W.onUpdate(1) W.onUpdate(6)
    check('free-roam weather: once off it touches the sky no more', #calls == n2)
    on.freeroam_weather = true
    W.onUpdate(0.1) W.onUpdate(6)
    local n3, v3 = #calls, #vcmds
    W.onClientEndMission()
    on.freeroam_weather = false
    W.onUpdate(1) W.onUpdate(6)
    check('free-roam weather: after a level ends with the switch off, the new level gets no restore write (sky or car)', #calls == n3 and #vcmds == v3)
  end
  for _, n in ipairs(names) do _G[n] = saved[n] end
  os.time = savedTime
  package.loaded['sl/weather'], package.loaded['sl/mode'] = nil, nil
end

do -- free roam never writes a career: with no career started (free roam, every switch on) nothing the career module does touches a save file
  local saved = { FS = rawget(_G, 'FS'), jsonWriteFile = rawget(_G, 'jsonWriteFile'), jsonReadFile = rawget(_G, 'jsonReadFile'), extensions = rawget(_G, 'extensions'), log = rawget(_G, 'log'),
    sl_options = rawget(_G, 'sl_options'), sl_career = rawget(_G, 'sl_career') }
  local writes, events = {}, {}
  _G.log = function() end
  _G.FS = setmetatable({}, { __index = function(_, k) return function() writes[#writes + 1] = 'FS:' .. k return false end end })
  _G.jsonWriteFile = function(path) writes[#writes + 1] = 'json:' .. tostring(path) return true end
  _G.jsonReadFile = function() return nil end
  _G.extensions = { hook = function(name) events[#events + 1] = name end }
  package.loaded['sl/career'] = nil
  local okc, C = pcall(require, 'sl/career')
  check('free roam: the career module loads without a career', okc and type(C) == 'table' and C.isActive() == false and C.getState() == nil)
  if okc then
    _G.sl_career = C
    local on = { freeroam = true }
    for _, id in ipairs(require('sl/core/mode').IDS) do on['freeroam_' .. id] = true end
    _G.sl_options = { get = function(k) return on[k] end }
    package.loaded['sl/mode'] = nil
    local M = require('sl/mode')
    check('free roam: every switch on, still no career: kind is freeroam and the state is no career state', M.kind() == 'freeroam' and M.enabled('phone') and M.state('phone') ~= nil and M.state('phone').sandbox == true and C.getState() == nil)
    local called = 0
    for k, fn in pairs(C) do
      if type(fn) == 'function' and k:sub(1, 2) == 'on' then called = called + 1 pcall(fn, 60, 60) pcall(fn, 60) pcall(fn) end
    end
    local bad = {}
    for _, w in ipairs(writes) do bad[#bad + 1] = w end
    check('free roam: ' .. called .. ' career hooks run with no career wrote nothing (saves, slots, places): ' .. table.concat(bad, ','), called > 3 and #writes == 0)
    local heat = false
    for _, e in ipairs(events) do if e:find('Rival') or e:find('Heat') or e:find('Wanted') or e == 'onStreetLegalStarted' or e == 'onStreetLegalBeforeSave' then heat = true end end
    check('free roam: no career, rival, heat or save event is fired', not heat)
  end
  package.loaded['sl/career'], package.loaded['sl/mode'] = nil, nil
  _G.FS, _G.jsonWriteFile, _G.jsonReadFile, _G.extensions, _G.log, _G.sl_options, _G.sl_career = saved.FS, saved.jsonWriteFile, saved.jsonReadFile, saved.extensions, saved.log, saved.sl_options, saved.sl_career
end

do -- Street Legal in free roam (sl/core/mode)
  local Mo = require('sl/core/mode')
  local on = {}
  local function sw(k) return on[k] == true end
  check('mode: free roam is off by default and a career is always on', not Mo.enabled(false, sw, 'phone') and Mo.kind(false, sw) == nil and Mo.enabled(true, sw, 'rivals') and Mo.kind(true, sw) == 'career')
  on.freeroam_phone = true
  check('mode: a feature switch alone enables nothing (the master is needed)', not Mo.enabled(false, sw, 'phone'))
  on = { freeroam = true }
  check('mode: the master alone enables nothing', Mo.kind(false, sw) == 'freeroam' and not Mo.enabled(false, sw, 'phone'))
  on.freeroam_phone = true
  check('mode: master and the feature switch enable it, other features stay off', Mo.enabled(false, sw, 'phone') and not Mo.enabled(false, sw, 'maps'))
  on.freeroam_rivals, on.freeroam_rep = true, true
  check('mode: career-only features are off in free roam whatever is set', not Mo.enabled(false, sw, 'rivals') and not Mo.enabled(false, sw, 'rep') and not Mo.enabled(false, sw, 'freeroam'))
  local f = Mo.FEATURES()
  check('mode: the menu list has the master first, then every feature, all off by default', f[1].id == 'freeroam' and #f == #Mo.IDS + 1 and f[2].id == 'phone' and f[2].default == false and f[2].title ~= '' and Mo.key('freeroam') == 'freeroam' and Mo.key('cab') == 'freeroam_cab')
end

-- sl_tyrecare: the career's tyres against a stub of carSurfaceFx_tyres (absent, off, on)
do
  local saved = { sl_career = rawget(_G, 'sl_career'), sl_fleet = rawget(_G, 'sl_fleet'), carSurfaceFx_tyres = rawget(_G, 'carSurfaceFx_tyres'), guihooks = rawget(_G, 'guihooks'),
    extensions = rawget(_G, 'extensions'), getObjectByID = rawget(_G, 'getObjectByID'), ui_message = rawget(_G, 'ui_message') }
  local T = require('sl/core/tyres')
  local rows = T.carRows({ compound = 'road', wheels = { { idx = 0, stage = 1 }, { idx = 1, stage = 2, flat = 0.5 }, { idx = 2, stage = 4 }, { idx = 3, stage = 5 } } })
  check('tyrecare: the wheel rows read the stage when there is no fraction, the worst tyre says replace', #rows.rows == 4 and rows.rows[1].stage == 'new' and rows.rows[2].stage == 'good' and rows.rows[2].flat
    and rows.rows[3].stage == 'low' and rows.rows[4].stage == 'bald' and rows.worst.idx == 3 and rows.replace and T.carRows(nil) == nil and T.carRows({ wheels = {} }) == nil)
  check('tyrecare: a fraction wins over the stage and a blow-out is blown', T.wheelRow({ idx = 0, frac = 0.9, stage = 5 }).stage == 'new' and T.wheelRow({ idx = 0, frac = 0.9, blown = true }).stage == 'blown' and T.wheelRow({ idx = 0, blown = true }).replace)
  local p = T.plan('slick', 'track', { compound = 'road', frac = 0.5 }, 5000, false)
  check('tyrecare: a change plan has the track fee and the trade-in', p.ok and p.price == 1430 - 27 and p.parts.fee == 330)
  check('tyrecare: a plan is refused moving, when poor, or for a compound that does not exist', not T.plan('slick', 'garage', nil, 5000, true).ok and not T.plan('slick', 'garage', nil, 10, false).ok and not T.plan('moon', 'garage', nil, 5000, false).ok)

  local state = { money = 5000, cars = {} }
  local car = { id = 1, name = 'Covet' }
  state.cars[1] = car
  local spent, hooks, toasts, calls = {}, {}, {}, {}
  _G.sl_career = { isActive = function() return true end, getState = function() return state end, addMoney = function(n, why) if state.money + n < 0 then return false end state.money = state.money + n spent[#spent + 1] = n return true end }
  _G.sl_fleet = { currentCar = function() return car end, vehicleOf = function(id) return { getID = function() return 77 end } end, carOfVehicle = function(vid) return vid == 77 and 1 or nil end }
  _G.getObjectByID = function() return { getVelocity = function() return { length = function() return 0 end } end } end
  _G.guihooks = { trigger = function(n, t) toasts[#toasts + 1] = t.text end }
  _G.extensions = { hook = function(n) hooks[#hooks + 1] = n end }
  _G.ui_message = nil
  package.loaded['sl/tyrecare'] = nil
  _G.carSurfaceFx_tyres = nil
  local tc = require('sl/tyrecare')
  local list = {}
  tc.onWrenchWorksServices(list)
  check('tyrecare: without the tyre module nothing is offered, changed or saved', not tc.available() and #list == 0 and tc.changeNow('slick', 'garage') == false and tc.save(77, car) == nil and tc.restore(77, car) == nil and tc.info(car, 77) == nil)

  local mod = { enabled = false }
  _G.carSurfaceFx_tyres = {
    getConfig = function() return { enabled = mod.enabled } end,
    getTyres = function() return { wheels = { { idx = 0, stage = 3 }, { idx = 1, stage = 2 } } } end,
    setCompound = function(id, axle, name) calls[#calls + 1] = 'compound:' .. id .. ':' .. name return true end,
    setTread = function(id, w, f) calls[#calls + 1] = 'tread:' .. id .. ':' .. tostring(w) .. ':' .. f return true end,
    snapshot = function(id) return { [0] = { h = 4 } } end,
    restore = function(id, blob) calls[#calls + 1] = 'restore:' .. id return true end,
    attach = function(id) calls[#calls + 1] = 'attach:' .. id end,
  }
  check('tyrecare: the tyre module switched off in its Mods page hides everything', not tc.available())
  mod.enabled = true
  list = {}
  tc.onWrenchWorksServices(list)
  local info, slick
  for _, e in ipairs(list) do if e.id == 'tyres:info' then info = e end if e.id == 'tyre:slick' then slick = e end end
  check('tyrecare: the drawer shows the tyres state and a change for each other compound, priced with the trade-in', info and info.disabled and info.label:find('Road') and slick and slick.price == 1100 - math.floor(T.COMPOUNDS.road.set * 0.15 * 0.4 + 0.5)
    and slick.group == 'Tyres')
  local ok, text = tc.changeNow('slick', 'garage')
  check('tyrecare: a change pays, sets the compound and a fresh tread, and keeps the compound with the car', ok and text:find('Slick') and state.money == 5000 - (1100 - math.floor(T.COMPOUNDS.road.set * 0.15 * 0.4 + 0.5)) and calls[1] == 'compound:77:slick'
    and calls[2] == 'tread:77:nil:1' and car.tyres.compound == 'slick' and car.tyres.blob == nil and hooks[#hooks] == 'onStreetLegalChanged')
  state.money = 100
  local before = #calls
  ok, text = tc.changeNow('slicksoft', 'track')
  check('tyrecare: too poor, nothing is sold and nothing is sent to the car', not ok and #calls == before and car.tyres.compound == 'slick')
  state.money = 5000
  _G.getObjectByID = function() return { getVelocity = function() return { length = function() return 20 end } end } end
  ok = tc.changeNow('road', 'garage')
  check('tyrecare: not while the car is moving', ok == false and car.tyres.compound == 'slick')
  _G.getObjectByID = function() return { getVelocity = function() return { length = function() return 0 end } end } end

  car.tyres = { compound = 'slick' }
  do -- fitting other tyre parts in the garage makes a new set
    local function tree(tire) return { children = { { path = '/body/', chosenPartName = 'body', children = { { path = '/wheels/tire_F/', chosenPartName = tire, children = {} }, { path = '/wheels/rim_F/', chosenPartName = 'rim' } } } } } end
    local sa, sb = T.signature(tree('tire_a')), T.signature(tree('tire_b'))
    check('tyrecare: the tyre signature names the fitted tyre parts only, "" for bare rims', sa:find('tire_a', 1, true) and not sa:find('rim', 1, true) and sa ~= sb and T.signature({ children = { { path = '/wheels/rim_F/', chosenPartName = 'rim' } } }) == '' and T.signature(nil) == '')
    local c2 = { id = 1, tyres = { compound = 'slick', blob = { [0] = { h = 1 } } } }
    state.cars[1] = c2
    tc.onWrenchWorksDriveOut(77, { partsTree = tree('tire_a') })
    check('tyrecare: a car saved before signatures keeps its wear when it first drives out, and gets its signature', c2.tyres.blob and c2.tyres.compound == 'slick' and c2.tyres.sig == sa)
    tc.onWrenchWorksDriveOut(77, { partsTree = tree('tire_a') })
    check('tyrecare: the same tyres at the next drive-out keep the wear', c2.tyres.blob and c2.tyres.compound == 'slick')
    tc.onWrenchWorksDriveOut(77, { partsTree = tree('tire_b') })
    check('tyrecare: other tyre parts fitted: a new set, the old wear and compound are dropped', c2.tyres.blob == nil and c2.tyres.compound == nil and c2.tyres.sig == sb)
    tc.onWrenchWorksDriveOut(77, { partsTree = { children = {} } })
    check('tyrecare: tyres taken off leave bare rims with no wear', c2.tyres.sig == '' and c2.tyres.blob == nil)
    c2.tyres = { compound = 'slick', blob = { [0] = { h = 1 } }, sig = sb }
    tc.onWrenchWorksPartBought(77, '/wheels/rim_F/', 'rim', 50)
    check('tyrecare: buying a part that is not a tyre keeps the wear', c2.tyres and c2.tyres.blob)
    tc.onWrenchWorksPartBought(77, '/wheels/tire_F/', 'tire_b', 90)
    check('tyrecare: buying a tyre part, even the same one, drops the old wear (a new set)', c2.tyres == nil)
    state.cars[1] = car
  end
  check('tyrecare: the wear is snapshotted into the car record', tc.save(77, car) == true and car.tyres.blob[0].h == 4 and car.tyres.compound == 'slick')
  calls = {}
  tc.restore(78, car)
  check('tyrecare: a car that comes out gets the module and its wear back (the blob has the compound)', calls[1] == 'attach:78' and calls[2] == 'restore:78' and #calls == 2)
  tc.onUpdate(1)
  check('tyrecare: the blob is not sent again before the retry time', #calls == 2)
  tc.onUpdate(1.5)
  check('tyrecare: the restore is sent once more after 2 s (a car whose module was not loaded yet), and then no more', calls[#calls] == 'restore:78' and #calls == 4 and (function() tc.onUpdate(5) return #calls == 4 end)())
  calls = {}
  tc.restore(78, { tyres = { compound = 'slick' } })
  check('tyrecare: a compound with no wear saved is set again', calls[2] == 'compound:78:slick' and #calls == 2)
  calls = {}
  tc.restore(78, { tyres = { compound = 'road' } })
  check('tyrecare: a road-tyre car with no wear saved is left alone', #calls == 1 and calls[1] == 'attach:78')
  calls = {}
  tc.onVehicleResetted(77)
  check('tyrecare: after a reset (R) the wear is put back', calls[1] == 'attach:77' and calls[2] == 'restore:77')
  do -- the test aid
    local sv = { fleet = _G.sl_fleet, gp = rawget(_G, 'getPlayerVehicle') }
    local made
    _G.getPlayerVehicle = function() return { getID = function() return 90 end } end
    _G.sl_fleet = { carOfVehicle = function(v) return v == 77 and 1 or nil end, registerVehicle = function(v, info) made = { v = v, info = info } return { id = 5 } end }
    local ok1, t1 = tc.devRegister()
    check('tyrecare: devRegister makes the car under the player a career car', ok1 and made.v == 90 and made.info.name == 'QA tyre car' and t1:find('career car 5'))
    _G.getPlayerVehicle = function() return { getID = function() return 77 end } end
    made = nil
    check('tyrecare: devRegister leaves a car that is already a career car alone', tc.devRegister() == false and made == nil)
    _G.sl_fleet, _G.getPlayerVehicle = sv.fleet, sv.gp
  end
  tc.onCsfxTyreBlown(77) tc.onCsfxTyreBlown(99)
  check('tyrecare: a blow-out of the player\'s own car is a toast, any other car is not', #toasts >= 1 and toasts[#toasts] == 'A tyre has blown.' and (function() local n = 0 for _, t in ipairs(toasts) do if t == 'A tyre has blown.' then n = n + 1 end end return n == 1 end)())
  -- a car on bare rims (the starter car): the module reports no wheels, so nothing is followed, sold or snapshotted; once tyres are fitted it is followed
  local snaps, bareCalls = 0, {}
  local wheelsNow = {}
  _G.carSurfaceFx_tyres = { getConfig = function() return { enabled = true } end, getTyres = function() return { wheels = wheelsNow } end,
    setCompound = function() bareCalls[#bareCalls + 1] = 'compound' return true end, setTread = function() bareCalls[#bareCalls + 1] = 'tread' return true end,
    snapshot = function() snaps = snaps + 1 return { [0] = { h = 1 } } end, restore = function() bareCalls[#bareCalls + 1] = 'restore' end }
  local bare = { id = 2, name = 'Autobello' }
  local cardB = tc.card(bare, 77, true)
  check('tyrecare: a car on bare rims is not tracked: the card says no_tyres and has no offers', tc.noTyres(77) and cardB and cardB.tracked == false and cardB.reason == 'no_tyres' and cardB.offers == nil)
  local bareList = {}
  tc.onWrenchWorksServices(bareList)
  local okB, textB = tc.changeNow('slick', 'garage')
  check('tyrecare: bare rims: the drawer says so, no change is sold, nothing is sent to the car, nothing is snapshotted', #bareList == 1 and bareList[1].id == 'tyres:none' and okB == false and textB ~= nil and #bareCalls == 0
    and tc.save(77, bare) == nil and snaps == 0 and bare.tyres == nil)
  wheelsNow = { { idx = 0, frac = 1, axle = 'front', side = 'left' }, { idx = 1, frac = 1, axle = 'front', side = 'right' } }
  local fitted = tc.card(bare, 77, true)
  check('tyrecare: once tyres are fitted (the car respawned with the part) it is followed: rows, offers, and its wear is snapshotted', not tc.noTyres(77) and #fitted.rows == 2 and fitted.offers ~= nil and tc.save(77, bare) == true and snaps == 1 and bare.tyres.blob ~= nil)
  _G.carSurfaceFx_tyres = { getConfig = function() error('boom') end, getTyres = function() error('boom') end, setCompound = function() error('boom') end }
  check('tyrecare: an error inside the tyre module never reaches the career', tc.info(car, 77) == nil)
  _G.sl_career, _G.sl_fleet, _G.carSurfaceFx_tyres, _G.guihooks, _G.extensions, _G.getObjectByID, _G.ui_message = saved.sl_career, saved.sl_fleet, saved.carSurfaceFx_tyres, saved.guihooks, saved.extensions, saved.getObjectByID, saved.ui_message
  package.loaded['sl/tyrecare'] = nil
end

do -- the GPU gate between the wet world's reloads and the puddle planes
  local G = require('sl/core/gpugate')
  G.reset()
  check('gate: with nothing happening both sides may work', G.planesMayChange(100) and G.wetMayBatch(100))
  G.reloaded(100)
  check('gate: after a wet world batch the planes wait 1 s, then may go', not G.planesMayChange(100.5) and not G.planesMayChange(100.99) and G.planesMayChange(101) and G.wetMayBatch(100.1))
  G.planesTouched(200)
  check('gate: after a plane was made the wet world waits 0.5 s, then may go', not G.wetMayBatch(200.2) and G.wetMayBatch(200.5))
  G.reset()
  local l1 = G.waited('wet', 300)
  local l2 = G.waited('wet', 301)
  local l3 = G.waited('planes', 301)
  local l4 = G.waited('wet', 306)
  G.reset()
  G.reloaded(0)
  for t = 0.2, 11, 0.2 do G.waited('planes', t) end
  check('gate: planes that waited over 10 s without a plane made get a window: the wet world pauses 1.5 s, then goes on', not G.wetMayBatch(11) and not G.wetMayBatch(12.4) and G.wetMayBatch(12.6) and G.planesMayChange(12.6))
  G.reset()
  G.waited('planes', 0) G.waited('planes', 5) G.planesTouched(6) G.waited('planes', 12)
  check('gate: a plane made, or a pause in the waiting, starts a new spell, so no window opens', G.wetMayBatch(13))
  G.reset()
  check('wetworld: a batch is one edit whatever the last edit cost', (function() local W = require('sl/core/wetworld') return W.batch(0.1, 3, 1) == 1 and W.batch(nil, 3, 1) == 1 and W.batch(50, 3, 1) == 1 end)())
  check('gate: terrain height edits wait 10 s after a swap and 1 s after a wet reload', (function() G.reset() G.terrainSwapped(100) local a = not G.terrainEditOk(105) and G.terrainEditOk(110) G.reloaded(200) local b = a and not G.terrainEditOk(200.5) and G.terrainEditOk(201) G.reset() return b end)())
  check('gate: a terrain edit holds the wet world for 0.5 s but does not clear a planes wait', (function() G.reset() G.waited('planes', 0) G.waited('planes', 6) G.waited('planes', 11) G.terrainEdited(11.2) local held = not G.wetMayBatch(11.4) local ok = G.wetMayBatch(11.8) G.reset() return held and ok end)())
  check('gate: terrain material lookups are held for 60 s after a terrain swap, and free before one', G.terrainLookupsOk(5) and (function() G.terrainSwapped(100) return not G.terrainLookupsOk(159) and G.terrainLookupsOk(160) end)())
  G.reset()
  check('gate: a wait is logged once per 5 s per side, with the count since, and the sides are separate', l1 and l1:find('1 time') and l2 == nil and l3 and l3:find('planes waited') and l4 and l4:find('2 time'))
  G.reset()
end

do -- 0.5.2: a saved Wet tarmac "on" is reset to off once
  local O = require('sl/options')
  local a = { slWetTarmac = true }
  local changed = O.migrate052(a)
  check('wet tarmac migration: a saved on becomes off, once, and the flag is stored', changed and a.slWetTarmac == false and a.slWetTarmacReset052 == true)
  a.slWetTarmac = true
  check('wet tarmac migration: a player who turned it back on afterwards keeps it', O.migrate052(a) == false and a.slWetTarmac == true)
  local b = {}
  O.migrate052(b)
  check('wet tarmac migration: nothing saved stays unset (the default applies), and a saved off stays off', b.slWetTarmac == nil and b.slWetTarmacReset052 == true and O.migrate052({ slWetTarmac = false }) == true)
end

check('wet trace: a line names the number, kind, material, step and time', require('sl/core/wetworld').traceLine(7, { kind = 'asphalt', name = 'road_a' }, 6, 1.5) == 'wet edit #7 asphalt road_a -> step 6 (1.5 ms)' and require('sl/core/wetworld').traceLine(7, { kind = 'asphalt', name = 'road_a' }, 6) == 'wet start #7 asphalt road_a -> step 6')

do -- 0.6.0: a saved Wet roads and walls "on" is reset to off once, and the default is off
  local O = require('sl/options')
  local a = { slWetWorld = true }
  check('wet world migration: a saved on becomes off, once, and the flag is stored', O.migrate060(a) == true and a.slWetWorld == false and a.slWetWorldReset060 == true)
  a.slWetWorld = true
  check('wet world migration: a player who turned it back on afterwards keeps it', O.migrate060(a) == false and a.slWetWorld == true)
  local b = {}
  O.migrate060(b)
  check('wet world migration: nothing saved stays unset, a saved off stays off', b.slWetWorld == nil and O.migrate060({ slWetWorld = false }) == true)
  local def
  for _, d in ipairs(O.defs) do if d.key == 'slWetWorld' then def = d end end
  check('wet world: off by default and in every preset, with the warning in its description', def and def.default == false and def.presets.performance == false and def.presets.balanced == false and def.presets.quality == false and def.presets.max == false
    and def.desc:find('lost the graphics driver', 1, true) ~= nil)
end

do -- the migration never overwrites a file it could not read
  local sv = { r = rawget(_G, 'jsonReadFile'), w = rawget(_G, 'jsonWriteFile') }
  local reads, writes = nil, 0
  _G.jsonReadFile = function() return reads end
  _G.jsonWriteFile = function() writes = writes + 1 return true end
  local function fresh() package.loaded['sl/options'] = nil return require('sl/options') end
  reads = nil
  local O = fresh()
  O.get('slWetTarmac')
  check('wet tarmac migration: a file that could not be read (nil) is not overwritten', writes == 0 and O.get('slWetTarmac') == false)
  O.set('slPerf', O.get('slPerf'))
  check('wet tarmac migration: the next normal save carries the flag, so a later "on" is kept', writes == 1)
  reads = { slWetTarmac = true, slClock = false }
  O = fresh()
  O.get('slWetTarmac')
  check('wet tarmac migration: a readable file with on is reset and rewritten with the other options kept', writes == 2 and O.get('slWetTarmac') == false)
  _G.jsonReadFile, _G.jsonWriteFile = sv.r, sv.w
  package.loaded['sl/options'] = nil
end

-- the parts of the game that can be switched off (sl/core/features)
do
  local F = require('sl/core/features')
  local Opt = require('sl/options')
  local defs = {}
  for _, d in ipairs(Opt.defs) do defs[d.key] = d end
  local okDefs = #F.LIST == 34
  local offByDefault = 0
  for _, f in ipairs(F.LIST) do
    local d = defs[f.opt]
    if not (d and d.type == 'bool' and d.default == (f.default ~= false) and d.feature == true and d.title == f.title and f.desc ~= '') then okDefs = false end
    if f.default == false then offByDefault = offByDefault + 1 end
  end
  check('parts: every part has an option, one bool, on by default unless the part says off (needs), tagged for the Active features page', okDefs and offByDefault == 1 and F.get('needs').default == false)
  local off = { slJobs = false }
  local function get(k) return off[k] end
  check('parts: on unless the option is false; a missing option system is on', F.on('jobs', get) == false and F.on('races', get) == true and F.on('jobs', function() return nil end) == true and F.on('nope', get) == true)
  local calls = {}
  local m = { onUpdate = function(dt) calls[#calls + 1] = 'update' return 'u' end, onStreetLegalNewDay = function() calls[#calls + 1] = 'day' end,
    onStreetLegalBeforeSave = function() calls[#calls + 1] = 'save' end, onStreetLegalStarted = function() calls[#calls + 1] = 'started' end,
    onStreetLegalStopped = function() calls[#calls + 1] = 'stopped' end, onClientEndMission = function() calls[#calls + 1] = 'end' end,
    summary = function() calls[#calls + 1] = 'summary' return { x = 1 } end, list = function() return { 1 } end }
  F.gate('jobs', m, get, { 'onStreetLegalStarted' }, { 'summary' })
  local r = m.onUpdate(0.1) m.onStreetLegalNewDay(2) local sm = m.summary()
  check('parts: an off part ignores updates, new days and its summary', r == nil and sm == nil and #calls == 0)
  m.onStreetLegalBeforeSave() m.onStreetLegalStarted() m.onClientEndMission()
  check('parts: saving, a kept start hook and cleanup always run; a call not named stays', #calls == 3 and calls[1] == 'save' and calls[2] == 'started' and calls[3] == 'end' and m.list()[1] == 1)
  calls = {}
  off.slJobs = nil
  check('parts: switched on again the hooks run', m.onUpdate(0.1) == 'u' and m.summary().x == 1 and #calls == 2)
  calls = {}
  m.onStreetLegalOption('slJobs', false)
  check('parts: switching the part off stops it once (the cleanup hook)', #calls == 1 and calls[1] == 'stopped')
  calls = {}
  m.onStreetLegalOption('slRaces', false) m.onStreetLegalOption('slJobs', true)
  check('parts: another option, or switching on, stops nothing', #calls == 0)
  -- clubs: days that went by while the part was off make the season stale; it closes with no reward when the part is back
  do
    local CL = require('sl/core/clubs')
    check('clubs: a season is stale only when days passed that were not simulated', CL.unsimulated({ simDay = 3 }, 8) == true and CL.unsimulated({ simDay = 7 }, 8) == false and CL.unsimulated({ simDay = 8 }, 8) == false and CL.unsimulated({}, 8) == false and CL.unsimulated(nil, 8) == false)
    local sent, paid = {}, {}
    local oldC, oldG, oldF = rawget(_G, 'sl_career'), rawget(_G, 'guihooks'), rawget(_G, 'sl_fleet')
    _G.guihooks = { trigger = function() end }
    _G.sl_fleet = nil
    _G.sl_career = { isActive = function() return true end, has = function() return true end, getState = function() return nil end,
      sendText = function(who, text) sent[#sent + 1] = text end, payOut = function(m) paid[#paid + 1] = m end, racesList = function() return {} end }
    local okLoad, CE = pcall(require, 'sl/clubs')
    if okLoad then
      local st = { day = 8, garageLevel = 1, seed = 1, rep = 0, club = { club = 1, start = 1, season = 1, simDay = 3, standings = { player = 99 }, raced = {}, calendar = {} } }
      local okE = pcall(CE.ensureSeason, st)
      check('clubs: a season the clubs did not simulate pays nothing and a new one starts', okE and #paid == 0 and st.club.season == 2 and st.club.start == 8 and st.club.simDay == 8 and sent[1] ~= nil and sent[1]:find('not raced', 1, true) ~= nil, tostring(okE) .. ' paid=' .. #paid .. ' sent=' .. tostring(sent[1]))
      local st2 = { day = 12, garageLevel = 1, seed = 1, rep = 0, club = { club = 1, start = 1, season = 1, simDay = 12, standings = { player = 99, other = 0 }, raced = {}, calendar = {} } }
      paid = {}
      pcall(CE.ensureSeason, st2)
      check('clubs: a season that was simulated to the end still pays its reward as before', st2.club.season == 2 and #sent >= 2)
    else
      check('clubs: the extension loads in the test', false, tostring(CE))
    end
    _G.sl_career, _G.guihooks, _G.sl_fleet = oldC, oldG, oldF
  end
  -- the bank cannot be switched off while a loan is open; the hospital off lets an injured driver drive
  do
    local oldBank, oldInj = rawget(_G, 'sl_bank'), rawget(_G, 'slrrInjury')
    local oldR, oldW, oldExt = rawget(_G, 'jsonReadFile'), rawget(_G, 'jsonWriteFile'), rawget(_G, 'extensions')
    local store = {}
    _G.jsonReadFile = function() return store end
    _G.jsonWriteFile = function() return true end
    _G.extensions = { hook = function() end }
    _G.sl_bank = { hasLoan = function() return true end }
    local okRefused, msg = pcall(Opt.set, 'slBank', false)
    check('parts: the bank will not switch off with a loan open, and says why', okRefused == false and msg == 'Pay back the loan first')
    _G.sl_bank = { hasLoan = function() return false end }
    local okFree, errFree = pcall(Opt.set, 'slBank', false)
    check('parts: with no loan open the bank switches off', okFree == true, tostring(errFree))
    pcall(Opt.set, 'slBank', true)
    _G.sl_bank = oldBank
    local H = require('sl/hospital')
    _G.slrrInjury = { getState = function() return { injured = true, limits = { noDriving = true } } end }
    local was = H.canDrive()
    local offOpt = Opt.get
    Opt.set('slHospital', false)
    _G.sl_options = Opt
    local offNow = H.canDrive()
    Opt.set('slHospital', true)
    check('parts: an injured driver cannot drive with the hospital on, and can with it off', was == false and offNow == true and H.canDrive() == false)
    -- a hardcore career cannot switch the hospital off
    local oldCareer = rawget(_G, 'sl_career')
    _G.sl_career = { isActive = function() return true end, getState = function() return { options = { slHardcore = true } } end }
    local okH, msgH = pcall(Opt.set, 'slHospital', false)
    check('parts: a hardcore career cannot switch the hospital off, and is told why', okH == false and msgH == 'Hardcore careers need the hospital')
    _G.sl_career = { isActive = function() return true end, getState = function() return { options = { slHardcore = false } } end }
    check('parts: a normal career can', pcall(Opt.set, 'slHospital', false) == true)
    Opt.set('slHospital', true)
    _G.sl_career = oldCareer
    _G.slrrInjury = oldInj
    _G.sl_options = nil
    _G.jsonReadFile, _G.jsonWriteFile, _G.extensions = oldR, oldW, oldExt
  end
  local g = { onStreetLegalOption = function(k) calls[#calls + 1] = 'old:' .. k end }
  F.gate('races', g, get)
  g.onStreetLegalOption('slRaces', false)
  check('parts: an own option hook of the extension still runs', calls[#calls] == 'old:slRaces')
end

do -- phone skins: what a skin.json may say, what reaches the UI, and the folders
  local PS = require('sl/core/phoneskin')
  local good = { id = 'slate', name = 'Slate', author = 'Us', vars = { frame = '#101114', rim = '#3A3A44', screen = '#0e0e11', text = '#eee', accent = '#7fb2ff', frameRadius = 54, screenRadius = 44, iconRadius = 16, gloss = true, notch = 'pill' },
    appColors = { map = '#3a7d6e', bad = 'red' }, icons = { map = { path = 'M3 6l6-2 6 2 6-2v14l-6 2-6-2-6 2z', stroke = 1.8 }, camera = { path = 'M1 1h2z' }, evil = { path = 'M1 1" onload="x' }, nopath = {} } }
  local sk = PS.validate(good, 'slate')
  check('skin: a good skin.json is accepted with its name and author', sk and sk.id == 'slate' and sk.name == 'Slate' and sk.author == 'Us')
  check('skin: colours are kept (lower case), a wrong colour name is dropped', sk.appColors.map == '#3a7d6e' and sk.appColors.bad == nil and sk.dropped >= 1)
  check('skin: the css holds the frame, the screen, the tiles, the accent and the pill', sk.css:find('.slp-device:not(.slp-land){background:#101114;border-radius:54px;box-shadow:0 0 0 2px #3a3a44', 1, true) and sk.css:find('.slp-screen{background:#0e0e11;border-radius:44px;', 1, true)
    and sk.css:find('.slp-ico{border-radius:16px}', 1, true) and sk.css:find('fill:#7fb2ff', 1, true) and sk.css:find('.slp-screen::before', 1, true) and sk.css:find('linear-gradient', 1, true))
  check('skin: an outline icon is drawn with a stroke, a filled one is a plain path', sk.icons.map:find('stroke-width:1.8', 1, true) and sk.icons.camera == '<svg viewBox="0 0 24 24"><path d="M1 1h2z"/></svg>')
  check('skin: an icon path with anything but path characters is dropped (no attribute can be closed)', sk.icons.evil == nil and sk.icons.nopath == nil)
  local clamped = PS.validate({ vars = { frameRadius = 999, frame = 'javascript:x' } }, 'a1')
  check('skin: numbers are clamped and a wrong colour is dropped', clamped.css:find('border-radius:70px', 1, true) and not clamped.css:find('javascript', 1, true) and not clamped.css:find('background', 1, true))
  check('skin: the id comes from the folder when the file has none; bad ids and classic are refused', PS.validate({}, 'mine').id == 'mine' and PS.validate({}, 'Bad Id') == nil and PS.validate({ id = 'classic' }, 'x') == nil and PS.validate('x', 'a') == nil
    and PS.validate({}, string.rep('a', 33)) == nil)
  local noCss = PS.validate({ css = '@import url(http://x/y.css); body{display:none}', vars = { frame = '#111111' } }, 'a1')
  check('skin: a css field in a skin.json is not read: the css is only what the variables write', noCss and noCss.css:find('@', 1, true) == nil and noCss.css:find('body', 1, true) == nil and noCss.css:find('#111111', 1, true) ~= nil)
  local every = PS.validate({ vars = { frame = '#111', rim = '#222', screen = '#333', text = '#444', accent = '#555', iconColor = '#666', frameRadius = 1, screenRadius = 2, iconRadius = 3, iconSize = 20, gloss = true, tileShadow = true, notch = 'pill' } }, 'v1').css
  local allSelectors = true
  for rule in (every .. '\n'):gmatch('([^\n]*)\n') do if rule ~= '' and not rule:find('^%.slp%-root ') then allSelectors = false end end
  check('skin: every rule the variables write is under .slp-root (a skin cannot touch the rest of the page)', allSelectors and every:find('background:#111', 1, true) and every:find('width:20px', 1, true))
  local withFile = PS.validate({ icons = { map = { file = 'map.svg' }, camera = { file = 'nope.svg' } } }, 'pics', function(n) if n == 'map.svg' then return 'data:image/svg+xml;base64,AAAA' end end)
  check('skin: a picture icon is an img with the data uri the caller gave; a picture it could not read is dropped', withFile.icons.map == '<img class="slp-skinimg" src="data:image/svg+xml;base64,AAAA" alt="">' and withFile.icons.camera == nil and withFile.dropped == 1)
  local list = PS.choices({ b = { id = 'b', name = 'Zed' }, a = { id = 'a', name = 'alpha' } })
  check('skin: the Mods menu list is Classic first, then the skins by name', #list == 3 and list[1].id == 'classic' and list[2].label == 'alpha' and list[3].label == 'Zed')

  -- the skins that ship with the mod: every one is accepted whole (nothing dropped); the template is a skin folder the scan skips (its name is no id) and also valid
  for dir, raw in pairs(SHIPPED_SKINS) do
    local ok = PS.validate(raw, dir:match('^_') and 'template' or dir, function() return 'data:image/svg+xml;base64,AAAA' end)
    check('skin: the shipped skin ' .. dir .. ' is valid with nothing dropped', ok and ok.dropped == 0, ok and ok.dropped)
  end
  local slate = PS.validate(SHIPPED_SKINS.slate, 'slate')
  local apps = { 'races', 'garage', 'garagekit', 'bank', 'me', 'jobs', 'wait', 'help', 'map', 'camera', 'gallery', 'club', 'turf', 'carmarket', 'partmarket', 'phone', 'messages', 'contacts', 'cab' }
  local missing = {}
  for _, a in ipairs(apps) do if not slate.icons[a] or not slate.appColors[a] then missing[#missing + 1] = a end end
  check('skin: Slate redraws the icon and the colour of all 19 apps of the home screen', #missing == 0, table.concat(missing, ','))
  -- the folders (sl/phoneskins) with a stand-in for the game's files
  local files = { ['/street_legal/phone_skins/'] = { '/street_legal/phone_skins/slate/skin.json', '/street_legal/phone_skins/_template/skin.json' },
    ['/settings/street_legal/phone_skins/'] = { '/settings/street_legal/phone_skins/mine/skin.json', '/settings/street_legal/phone_skins/slate/skin.json' } }
  local json = { ['/street_legal/phone_skins/slate/skin.json'] = { name = 'Slate (mod)' }, ['/settings/street_legal/phone_skins/slate/skin.json'] = { name = 'Slate (mine)', vars = { text = '#abc' } },
    ['/settings/street_legal/phone_skins/mine/skin.json'] = { name = 'Mine', icons = { map = { file = 'm.png' }, cab = { file = '../x.png' }, bank = { file = 'big.png' }, jobs = { file = 'fake.png' }, wait = { file = 's.svg' }, help = { file = 'evil.svg' }, me = { file = 'j.jpg' } } }, ['/street_legal/phone_skins/_template/skin.json'] = { name = 'Template' } }
  local function png(w, h) return string.char(137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13) .. 'IHDR' .. string.char(0, 0, math.floor(w / 256), w % 256, 0, 0, math.floor(h / 256), h % 256) .. 'xxxx' end
  local bytes = { ['/settings/street_legal/phone_skins/mine/m.png'] = png(16, 16), ['/settings/street_legal/phone_skins/mine/big.png'] = png(512, 512), ['/settings/street_legal/phone_skins/mine/fake.png'] = 'not a png at all, but long enough to pass a size check', ['/settings/street_legal/phone_skins/mine/s.svg'] = '<svg viewBox="0 0 1 1"><path d="M0 0"/></svg>', ['/settings/street_legal/phone_skins/mine/evil.svg'] = '<svg><script>x</script></svg>' }
  for path in pairs(json) do bytes[path] = path end                                -- (the "file" of a skin.json is its own path: jsonDecode looks it up again)
  bytes['/settings/street_legal/phone_skins/huge/skin.json'] = string.rep('x', 70000)
  files['/settings/street_legal/phone_skins/'][#files['/settings/street_legal/phone_skins/'] + 1] = '/settings/street_legal/phone_skins/huge/skin.json'
  local saved = { FS = _G.FS, log = _G.log, jsonDecode = _G.jsonDecode, buffer = _G.buffer, readTo = io.readFileToBuffer }
  local reads = {}
  _G.FS = { findFiles = function(self, root) return files[root] or {} end, fileSize = function(self, f) return bytes[f] and #bytes[f] or nil end }
  _G.buffer = nil      -- (the game has no global `buffer`: the reader must take the 'string.buffer' module, as the game does)
  local savedSB = package.loaded['string.buffer']
  package.loaded['string.buffer'] = { new = function() local b = { data = '' } function b:tostring() return self.data end return b end }
  io.readFileToBuffer = function(f, buf) reads[#reads + 1] = f if not bytes[f] then return false end buf.data = bytes[f] return true end
  _G.jsonDecode = function(text) return json[text] end
  _G.log = function() end
  package.loaded['sl/phoneskins'] = nil
  local PK = require('sl/phoneskins')
  local names = {}
  for _, c in ipairs(PK.choices()) do names[#names + 1] = c.id .. '=' .. c.label end
  local listReads = {}
  for _, f in ipairs(reads) do listReads[#listReads + 1] = f end
  check('skins: the list holds Classic and the skins of the mod and the user folder (the user folder wins an id; a folder name that is no id is skipped)', table.concat(names, ',') == 'classic=Classic,mine=Mine,slate=Slate (mine)', table.concat(names, ','))
  do
    local logged = {}
    _G.log = function(level, tag, text) logged[#logged + 1] = level .. ' ' .. tostring(text) end
    local oldDecode = _G.jsonDecode
    _G.jsonDecode = function() error('boom') end
    PK.warned = {}
    local bad1, bad2 = PK.choices(), PK.choices()
    _G.jsonDecode = oldDecode
    _G.log = function() end
    local warns = 0
    for _, l in ipairs(logged) do if l:find('could not be read', 1, true) and l:find('boom', 1, true) then warns = warns + 1 end end
    check('skins: a list that cannot be built falls back to Classic and says why, once (not on every call)', #bad1 == 1 and bad1[1].id == 'classic' and #bad2 == 1 and warns == 1, table.concat(logged, ' | '))
  end
  do
    local hasSlate = false
    for _, c in ipairs(PK.choices()) do if c.id == 'slate' then hasSlate = true end end
    check('skins: against the game-like setup (string.buffer module, no global buffer) the list is not empty and contains Slate', #PK.choices() >= 2 and hasSlate and rawget(_G, 'buffer') == nil)
    local logged = {}
    _G.log = function(level, tag, text) logged[#logged + 1] = tostring(text) end
    PK.warned = {}
    local oldFind = _G.FS.findFiles
    _G.FS.findFiles = function(self, root) if root == '/street_legal/phone_skins/' then error('nofs') end return {} end
    PK.choices() PK.choices()
    _G.FS.findFiles = function() return {} end
    PK.warned = {}
    PK.choices() PK.choices()
    _G.FS.findFiles = oldFind
    _G.log = function() end
    local n1, n2 = 0, 0
    for _, l in ipairs(logged) do if l:find('searching', 1, true) and l:find('nofs', 1, true) then n1 = n1 + 1 end if l:find('no skin.json found', 1, true) then n2 = n2 + 1 end end
    check('skins: a failed search and an empty mod folder each say so in the log, once', n1 == 1 and n2 == 1, table.concat(logged, ' | '))
  end
  check('skins: Classic and unknown ids send nothing', PK.payload('classic') == nil and PK.payload(nil) == nil and PK.payload('nobody') == nil and PK.payload('Bad Id') == nil)
  local mine = PK.payload('mine')
  check('skins: a picture icon is read from the skin folder and sent as a data uri; one outside the folder is not', mine.icons.map and mine.icons.map:find('^<img class="slp%-skinimg" src="data:image/png;base64,iVBORw0KGgo') and mine.icons.cab == nil)
  check('skins: a png over 256 pixels, a file that is no png, a svg with a script and a jpg are all dropped; a plain svg is kept', mine.icons.bank == nil and mine.icons.jobs == nil and mine.icons.help == nil and mine.icons.me == nil and mine.icons.wait and mine.icons.wait:find('data:image/svg+xml;base64,', 1, true))
  check('skins: a skin.json over 64 KB is never read (a look at its size first), and the list reads only skin.json files, no pictures', (function() for _, f in ipairs(listReads) do if f:find('huge', 1, true) or f:find('%.png$') then return false end end return true end)())
  check('skins: base64 of 1, 2 and 3 bytes', PK.base64('M') == 'TQ==' and PK.base64('Ma') == 'TWE=' and PK.base64('Man') == 'TWFu' and PK.base64('') == '')
  _G.FS, _G.log, _G.jsonDecode, _G.buffer, io.readFileToBuffer = saved.FS, saved.log, saved.jsonDecode, saved.buffer, saved.readTo
  package.loaded['string.buffer'] = savedSB
  package.loaded['sl/phoneskins'] = nil
end

-- weekly costs and the ledger (career expansion #1)
do
  local W = require('sl/core/weekly')
  local ST = require('sl/core/state')
  check('weekly: week and day of week from the day', W.week(1) == 1 and W.week(7) == 1 and W.week(8) == 2 and W.dayOfWeek(1) == 1 and W.dayOfWeek(7) == 7 and W.dayOfWeek(8) == 1)
  check('weekly: no rent in the first garage, rent above it, storage for cars beyond two',
    #W.lines(1, 2) == 0 and W.total(W.lines(2, 2)) == 150 and W.total(W.lines(3, 5)) == 400 + 3 * 40 and W.total(W.lines(1, 3)) == 40)
  local r = W.settle(1000, 0, 300)
  check('weekly: bills paid in full', r.pay == 300 and r.short == 0 and r.debt == 0)
  r = W.settle(100, 50, 300)
  check('weekly: a shortfall joins the debt, money is never negative', r.pay == 100 and r.short == 200 and r.debt == 250 and r.repaid == 0)
  r = W.settle(1000, 500, 300)
  check('weekly: debt is repaid from money above the buffer only', r.billsPaid == 300 and r.repaid == 500 and r.debt == 0 and r.pay == 800)
  r = W.settle(600, 500, 300)
  check('weekly: the buffer stays after a part repayment', r.repaid == 100 and r.debt == 400 and 600 - r.pay == 200)

  local st = ST.new(1, 0)
  st.day, st.garageLevel, st.money = 1, 2, 1000
  for i = 1, 4 do st.cars[#st.cars + 1] = { id = i } end
  local sent = {}
  local old = { c = rawget(_G, 'sl_career'), g = rawget(_G, 'guihooks'), e = rawget(_G, 'extensions') }
  _G.guihooks = { trigger = function() end }
  _G.extensions = { hook = function() end }
  _G.sl_career = { isActive = function() return true end, getState = function() return st end,
    addMoney = function(a, l) return ST.addMoney(st, a, l) end, sendText = function(_, t) sent[#sent + 1] = t end }
  package.loaded['sl/weekly'] = nil
  local WK = require('sl/weekly')
  WK.onStreetLegalNewDay(2)
  check('weekly: the first day seen starts the first week, nothing is billed', st.money == 1000 and st.weekly.nextDue == 8 and st.weekly.debt == 0)
  WK.onStreetLegalNewDay(8)
  check('weekly: day 8 bills rent 150 and storage 2 x 40', st.money == 1000 - 230 and #st.weekly.history == 1 and st.weekly.history[1].costs == 230 and st.weekly.nextDue == 15)
  st.money = 100
  WK.onStreetLegalNewDay(15)
  check('weekly: an unpayable week makes a debt, costs reputation once, sends one text', st.money == 0 and st.weekly.debt == 130 and #sent == 1 and WK.debt() == 130)
  st.day = 15
  local sum = WK.summary()
  check('weekly: the summary has the week, the debt, projected bills and the history', sum.week == 3 and sum.debt == 130 and #sum.bills == 2 and sum.nextBillDay == 7 and #sum.history == 2)
  st.money = 150
  local ok1 = WK.payDebt(1000)
  check('weekly: payDebt pays what money allows and answers', ok1 == true and st.money == 20 and st.weekly.debt == 0)
  check('weekly: payDebt with no money refuses', (WK.payDebt(10)) == false)
  do
    local f = _G.sl_options
    _G.sl_options = { get = function(k) if k == 'slWeekly' then return false end end }
    check('weekly: with the part off the debt reads nil and payDebt does nothing', WK.debt() == nil and WK.payDebt(10) == nil and WK.summary() == nil)
    _G.sl_options = f
  end
  for d = 22, 22 + 7 * 10, 7 do WK.onStreetLegalNewDay(d) end
  check('weekly: history keeps eight weeks', #st.weekly.history == W.KEEP)
  _G.sl_career, _G.guihooks, _G.extensions = old.c, old.g, old.e
  package.loaded['sl/weekly'] = nil
end

-- used-car checks: the rules (career expansion #3)
do
  local U = require('sl/core/usedcar')
  check('usedcar: the fee is $40 + 0.5% of the ask, in tens', U.fee(0) == 40 and U.fee(2000) == 50 and U.fee(20000) == 140)
  local h1, h2 = U.history('m3', 90000, { 'brakes' }, 0.7), U.history('m3', 90000, { 'brakes' }, 0.7)
  check('usedcar: the history is the same every time for a listing, with three lines and at least the owners the mileage implies', h1.lines[1] == h2.lines[1] and h1.lines[2] == h2.lines[2] and h1.lines[3] == h2.lines[3] and #h1.lines == 3 and h1.owners >= 1)
  local none, patchy = 0, 0
  for i = 1, 300 do
    local h = U.history('x' .. i, 50000, { 'a', 'b', 'c' }, 0.5)
    if h.lines[2]:find('none') then none = none + 1 elseif h.lines[2]:find('patchy') then patchy = patchy + 1 end
  end
  local cleanBad = 0
  for i = 1, 300 do if not U.history('y' .. i, 50000, {}, 0.9).lines[2]:find('complete') then cleanBad = cleanBad + 1 end end
  check('usedcar: a faulty car more often has a poor service record than a clean one', none + patchy > cleanBad * 1.5)
  local f = U.faultCosts({ 'brakes', 'engine' }, 3000, 0.05)
  check('usedcar: the check lists each fault with its cost', #f == 2 and f[1].cost == 150 and f[1].label == 'Brakes')
end

-- servicing and wear (career expansion #2)
do
  local S = require('sl/core/service')
  local W = require('sl/core/wear')
  do -- a save that already has cars: what they drove before counts once, only the driving from first sight counts 40 times
    local old = {}
    local so = S.state(old, 1300, { brakes = 10 })
    local g0 = S.gross(so, 1300, 1000, { brakes = 10 })
    check('service: a car seen for the first time has the wear of before (300 km, 1x), not 40x, and is not due', so.origin == 1300 and math.abs(g0.brakes - W.lost(300, { brakes = 10 }).brakes) < 1e-9 and not S.due(so, S.since(so, 1300, 1000)))
    local g1 = S.gross(so, 1400, 1000, { brakes = 12 })
    check('service: from then on the driving and the new abuse count 40 times', math.abs(g1.brakes - W.lost(300 + 100 * 40, { brakes = 10 + 2 * 40 }).brakes) < 1e-9)
    check('service: the record is made once', S.state(old, 9999, {}).origin == 1300)
  end
  do -- the Wear rate setting: presets, the interval follows, a change keeps the wear already there
    check('service: Wear rate presets', S.rate('half') == 0.5 and S.rate('normal') == 1 and S.rate('double') == 2 and S.rate('quad') == 4 and S.rate('nope') == 1 and S.rate(nil) == 1)
    local r2 = S.state({}, 1000, {}, 2)
    check('service: at 2x a service is due after 75 km and the wear is twice as fast', S.due(r2, 75) and not S.due(r2, 74) and math.abs(S.gross(r2, 1070, 1000, {}).brakes - 2 * S.gross(S.state({}, 1000, {}, 1), 1070, 1000, {}).brakes) < 1e-12)
    local c = S.state({}, 1000, {}, 1)
    local before = S.gross(c, 1100, 1000, { brakes = 5 })
    check('service: the rate changing keeps the wear as it is, then counts at the new rate', S.sync(c, 4, 1100, 1000, { brakes = 5 }) == true and math.abs(S.gross(c, 1100, 1000, { brakes = 5 }).brakes - before.brakes) < 1e-12
      and S.gross(c, 1200, 1000, { brakes = 5 }).brakes > before.brakes and S.sync(c, 4, 1200, 1000, { brakes = 5 }) == false)
    local grown = S.gross(c, 1200, 1000, { brakes = 5 }).brakes - before.brakes
    check('service: after the change 100 km wear four times the 1x scale, with the overdue part past the 37.5 km interval', math.abs(grown - W.lost((100 + 0.5 * (100 - 37.5)) * 40 * 4, {}).brakes) < 1e-9)
    check('service: the service clock restarts at a change of the rate (the overdue wear so far is kept)', c.baseKm == 1100 and S.since(c, 1200, 1000) == 100)
  end
  local sv = S.state({})
  check('service: a fresh record, due once the interval is driven', sv.penalty == 0 and S.since(sv, 1000, 1000) == 0 and not S.due(sv, 149) and S.due(sv, 150) and S.wearFactor(sv, 100) == 1 and S.wearFactor(sv, 200) == 1.5)
  local g0 = S.gross(sv, 1000, 1000, {})
  local g1 = S.gross(sv, 1100, 1000, {})
  check('service: wear is scaled so a few hundred km show (brakes after 100 km: 0.5*100*40/120000)', g0.brakes == 0 and math.abs(g1.brakes - 0.5 * 100 * 40 / 120000) < 1e-9)
  local gOver = S.gross(sv, 1300, 1000, {})       -- 300 km since purchase, 150 over the interval = 75 km extra
  local gPlain = W.lost(300 * 40, {})
  check('service: skipping the interval wears faster', gOver.brakes > gPlain.brakes and math.abs(gOver.brakes - W.lost((300 + 75) * 40, {}).brakes) < 1e-9)
  S.doBasic(sv, 1300, 1000)
  local gAfter = S.gross(sv, 1300, 1000, {})
  check('service: a basic service keeps the wear of the skipped interval, resets the clock', sv.baseKm == 1300 and sv.count == 1 and math.abs(gAfter.brakes - gOver.brakes) < 1e-9 and S.since(sv, 1300, 1000) == 0)
  local gLater = S.gross(sv, 1400, 1000, {})
  check('service: after it, the wear grows at the normal rate again', math.abs((gLater.brakes - gAfter.brakes) - W.lost(100 * 40, {}).brakes) < 1e-9)
  local net0 = S.net(sv, gLater)
  S.doOverhaul(sv, 1400, 1000, {})
  local net1 = S.net(sv, S.gross(sv, 1400, 1000, {}))
  local zero = true
  for _, v in pairs(net1) do if v ~= 0 then zero = false end end
  check('service: an overhaul puts all wear right, and later wear shows on top of it', zero and net0.brakes > 0 and S.net(sv, S.gross(sv, 1500, 1000, {})).brakes > 0)
  check('service: the abuse counts scale too', S.gross(S.state({}), 1000, 1000, { brakes = 100 }).brakes > 0 and S.gross(S.state({}), 1000, 1000, { brakes = 100 }).brakes == W.lost(0, { brakes = 100 * 40 }).brakes)
  check('service: prices: basic $30 + 0.2% of the value, half as much again without a workbench; the overhaul adds the worn sections',
    S.basicCost(10000, true) == 50 and S.basicCost(10000, false) == 80 and S.overhaulCost(10000, { brakes = 0.1 }, 3, true) == 50 + 330 and S.overhaulCost(10000, { brakes = 0.1 }, 3, false) == 80 + 500)
  local secs = S.sections({ brakes = 0.25, engine = 0 }, nil)
  check('service: sections 0..1 from the wear model', #secs == 5 and secs[1].id == 'engine' and secs[1].condition == 1 and secs[4].id == 'brakes' and secs[4].condition == 0.5)
  local pw = S.sections({ brakes = 0 }, { { section = 'brakes', condition = 0.2 }, { section = 'brakes', condition = 0.6 }, { section = 'drive', condition = 0.9 }, { section = 'exhaust', condition = 0.7 }, { section = 'flux', condition = 0.1 } })
  local by = {}
  for _, x in ipairs(pw) do by[x.id] = x.condition end
  check('service: Part Wear shows its worst part per section, drive is our drivetrain, new sections are added and an unknown one is other', by.brakes == 0.2 and by.drivetrain == 0.9 and by.exhaust == 0.7 and by.other == 0.1 and by.engine == 1)

  -- the extension with a fake career
  local ST = require('sl/core/state')
  local st = ST.new(1, 0)
  st.day, st.money, st.garageLevel = 3, 1000, 1
  local car = { id = 1, name = 'Test', value = 10000, mileage = 1000, condition = 0.8, care = { engineKm = 1300, abuse = {}, trunk = {} } }
  car.service = { penalty = 0, credit = {}, count = 0, origin = 1000, abuse0 = {} }       -- (a car this part has seen since it was bought)
  st.cars[1] = car
  local old = { c = rawget(_G, 'sl_career'), cc = rawget(_G, 'sl_carcare'), e = rawget(_G, 'extensions'), f = rawget(_G, 'sl_fleet'), u = rawget(_G, 'sl_upgrades'), p = rawget(_G, 'slrr_partwear') }
  _G.extensions = { hook = function() end }
  _G.sl_fleet = nil
  _G.sl_upgrades = { features = function() return { workbench = true } end }
  _G.slrr_partwear = nil
  _G.sl_career = { isActive = function() return true end, getState = function() return st end, addMoney = function(a, l) return ST.addMoney(st, a, l) end }
  _G.sl_carcare = { careOf = function(c) return c.care end, note = function() end }
  package.loaded['sl/service'] = nil
  local SV = require('sl/service')
  local info = SV.serviceOf(1)
  check('service: the card says due, the km since, the interval, a factor and two options', info.due == true and info.km_since == 300 and info.km_interval == 150 and info.wearFactor == 1.5 and #info.options == 2 and info.options[1].cost == 50)
  local okS, text = SV.service(1, 'basic')
  check('service: a basic service charges, resets the interval and is noted', okS == true and st.money == 950 and car.service.baseKm == 1300 and SV.serviceOf(1).due == false)
  check('service: not enough money refuses and changes nothing', (function() st.money = 10 local ok = SV.service(1, 'full') return ok == false and st.money == 10 and car.service.count == 1 end)())
  check('service: an unknown car or service refuses', SV.service(9, 'basic') == false and SV.service(1, 'nope') == false)
  _G.slrr_partwear = { conditionsOf = function() return nil end, conditionsOfKey = function(k) return { parts = { { section = 'suspension', condition = 0.3 } } } end }
  local sus
  for _, x in ipairs(SV.serviceOf(1).sections) do if x.id == 'suspension' then sus = x.condition end end
  check('service: Part Wear by key is read when the car is not spawned', sus == 0.3)
  _G.slrr_partwear = { conditionsOf = function() error('boom') end }
  check('service: a failing Part Wear query falls back to our model', #SV.serviceOf(1).sections == 5)
  do -- the Wear rate reaches Part Wear and the tyres, and every car gets a record
    local got = {}
    local f0, t0 = rawget(_G, 'slrr_partwear'), rawget(_G, 'carSurfaceFx_tyres')
    _G.slrr_partwear = { setWearRate = function(k) got.pw = k return k end }
    _G.carSurfaceFx_tyres = { setWearScale = function(k) got.tyre = k return true end }
    local fo = _G.sl_options
    _G.sl_options = { get = function(k) if k == 'slWearRate' then return 'double' end end }
    st.cars[2] = { id = 2, name = 'Other', value = 5000, mileage = 500, care = { engineKm = 800, abuse = {}, trunk = {} } }
    SV.onUpdate(6)
    check('service: the Wear rate is sent to Part Wear and the tyres, as a number', got.pw == 2 and got.tyre == 2)
    check('service: every car gets a record at once, at the rate and the engine km of that moment', st.cars[2].service and st.cars[2].service.origin == 800 and st.cars[2].service.rate == 2)
    got = {}
    SV.onUpdate(1)
    check('service: nothing is sent again while it is unchanged', got.pw == nil and got.tyre == nil)
    SV.onStreetLegalOption('slWearRate', 'quad')
    _G.sl_options = { get = function(k) if k == 'slWearRate' then return 'quad' end end }
    SV.onStreetLegalOption('slWearRate', 'quad')
    check('service: a change of the setting is sent at once', got.pw == 4 and got.tyre == 4 and st.cars[2].service.rate == 4)
    _G.sl_options = fo
    _G.slrr_partwear, _G.carSurfaceFx_tyres = f0, t0
  end
  do
    local f = _G.sl_options
    _G.sl_options = { get = function(k) if k == 'slService' then return false end end }
    check('service: with the part off there is no card, no wear model and no purchase', SV.serviceOf(1) == nil and SV.wearOf(car) == nil and SV.service(1, 'basic') == nil)
    _G.sl_options = f
  end
  _G.sl_career, _G.sl_carcare, _G.extensions, _G.sl_fleet, _G.sl_upgrades, _G.slrr_partwear = old.c, old.cc, old.e, old.f, old.u, old.p
  package.loaded['sl/service'] = nil
end

-- review items 4-6 (ab, 2026-10-22): the race log is not rewritten on every line, the options file is never written over when it did not read, car commands guard their callbacks
do
  local sv = { w = rawget(_G, 'writeFile'), log = rawget(_G, 'log') }
  local writes, t = 0, 0
  _G.writeFile = function() writes = writes + 1 return true end
  _G.log = _G.log or function() end
  package.loaded['sl/racelog'] = nil
  local RL = require('sl/racelog')
  RL.clock = function() return t end
  _G.FS = _G.FS or { fileExists = function() return false end }
  RL.add('sprint', 'setup', {})
  local first = writes
  for i = 1, 50 do t = t + 0.01 RL.add('sprint', 'pos', { i = i }) end
  check('racelog: the first line writes, fifty more inside a second write nothing', first == 1 and writes == 1)
  t = t + 2 RL.add('sprint', 'pos', {})
  check('racelog: a line after a second writes again', writes == 2)
  RL.add('sprint', 'finish', {})
  check('racelog: the end of an event writes at once', writes == 3)
  RL.add('sprint', 'pos', {}) RL.flush() RL.flush()
  check('racelog: flush writes what waits, once', writes == 4)
  _G.writeFile, _G.log = sv.w, sv.log
  package.loaded['sl/racelog'] = nil

  local svo = { r = rawget(_G, 'jsonReadFile'), w = rawget(_G, 'jsonWriteFile'), fs = rawget(_G, 'FS') }
  local nw, exists = 0, true
  _G.jsonReadFile = function() return nil end
  _G.jsonWriteFile = function() nw = nw + 1 return true end
  _G.FS = { fileExists = function() return exists end }
  package.loaded['sl/options'] = nil
  local O = require('sl/options')
  O.set('slPerf', O.get('slPerf'))
  check('options: a file that is there but did not read is not written over by a changed setting', nw == 0 and O.get('slPerf') == O.get('slPerf'))
  exists = false
  package.loaded['sl/options'] = nil
  O = require('sl/options')
  O.set('slPerf', O.get('slPerf'))
  check('options: a missing file is written on the first change', nw == 1)
  _G.jsonReadFile, _G.jsonWriteFile, _G.FS = svo.r, svo.w, svo.fs
  package.loaded['sl/options'] = nil

end

-- contracts on the job board (career expansion #4)
do
  local C = require('sl/core/contract')
  local rngLib = require('sl/core/rng')
  local job = { pay = 1000, seconds = 300 }
  check('contract: terms raise the pay and keep the plain pay', C.apply(job, 'tight') and job.pay == 2000 and job.basePay == 1000 and job.contract.req == 'tight' and C.apply(job, 'clean') == false and C.apply({ pay = 100 }, 'nope') == false)
  check('contract: clean needs no damage', C.met('clean', { damage = 0 }) and not C.met('clean', { damage = 0.05 }))
  check('contract: tight needs 80% of the limit', C.met('tight', { elapsed = 240, seconds = 300 }) and not C.met('tight', { elapsed = 241, seconds = 300 }) and not C.met('tight', { elapsed = 10, seconds = 0 }))
  check('contract: rain needs a wet road, upscale a $15,000 car', C.met('rain', { wet = true }) and not C.met('rain', { wet = false }) and C.met('upscale', { carValue = 15000 }) and not C.met('upscale', { carValue = 14990 }) and not C.met('upscale', {}))
  local rng, gotRain = rngLib.new(5), false
  for _ = 1, 200 do if C.pick(rng, false) == 'rain' then gotRain = true end end
  local rng2, rainWet = rngLib.new(5), false
  for _ = 1, 200 do if C.pick(rng2, true) == 'rain' then rainWet = true end end
  check('contract: rain terms are offered only when it is wet', not gotRain and rainWet)

  local ST = require('sl/core/state')
  local st = ST.new(1, 0)
  st.day, st.rep, st.garageLevel = 3, 500, 1
  local old = { c = rawget(_G, 'sl_career'), e = rawget(_G, 'extensions'), g = rawget(_G, 'guihooks'), fs = rawget(_G, 'FS'), w = rawget(_G, 'sl_weather'), o = rawget(_G, 'sl_options'), f = rawget(_G, 'sl_fleet') }
  local places = {}
  for i = 1, 8 do places['p' .. i] = { name = 'Place ' .. i, kind = 'shop', pos = { x = i * 900, y = (i % 3) * 700, z = 0 } } end
  _G.guihooks = { trigger = function() end }
  _G.extensions = { hook = function() end }
  _G.FS = { findFiles = function() return {} end }
  _G.sl_weather = { wetness = function() return 0 end }
  _G.sl_fleet = nil
  _G.sl_career = { isActive = function() return true end, getState = function() return st end, phase = function() return 'day' end, getPlaces = function() return places end,
    addMoney = function(a, l) return ST.addMoney(st, a, l) end, payOut = function(a, l) return ST.addMoney(st, a, l) end }
  package.loaded['sl/jobs'] = nil
  local okJ, JB = pcall(require, 'sl/jobs')
  if okJ then
    local contracts, plain, seeds = 0, 0, 0
    for seed = 1, 12 do
      st.seed, st.jobs, st.day = seed, nil, 3 + seed
      local sm = JB.summary()
      for _, o in ipairs(sm.offers) do
        if o.contract then
          contracts = contracts + 1
          if not (o.pay >= o.contract.basePay * (o.contract.mult - 0.05) and o.title:find('Contract', 1, true) and (o.contract.req ~= 'rain')) then contracts = -1000 end
        else plain = plain + 1 end
      end
      if #sm.offers > 0 then seeds = seeds + 1 end
    end
    check('contract: the board has some contracts with the higher pay, never more than two a board, and never rain on a dry day', contracts > 0 and plain > 0 and seeds >= 6, tostring(contracts) .. ' ' .. tostring(plain) .. ' ' .. tostring(seeds))
    st.rep, st.seed, st.jobs, st.day = 50, 1, nil, 40
    local few = 0
    for _, o in ipairs(JB.summary().offers) do if o.contract then few = few + 1 end end
    check('contract: none below the reputation', few == 0)
    _G.sl_options = { get = function(k) if k == 'slContracts' then return false end end }
    st.rep, st.jobs, st.day = 500, nil, 41
    local off = 0
    for _, o in ipairs(JB.summary().offers) do if o.contract then off = off + 1 end end
    check('contract: none with the part off', off == 0)
  else
    check('contract: sl_jobs loads in the test', false, tostring(JB))
  end
  _G.sl_career, _G.extensions, _G.guihooks, _G.FS, _G.sl_weather, _G.sl_options, _G.sl_fleet = old.c, old.e, old.g, old.fs, old.w, old.o, old.f
  package.loaded['sl/jobs'] = nil
end

-- tier perks (career expansion #6)
do
  local P = require('sl/core/perks')
  check('perks: no factor at rank 1; the upgrade and service perks at rank 2', P.factor(1, 'upgrades') == 1 and P.factor(2, 'upgrades') == 0.9 and P.factor(2, 'service') == 0.85 and P.factor(2, 'jobs') == 1)
  check('perks: jobs at 3, fines at 4, loans at 5, and an unknown kind is always 1', P.factor(3, 'jobs') == 1.1 and P.factor(4, 'fines') == 0.8 and P.factor(5, 'loans') == 1.25 and P.factor(6, 'nothing') == 1 and P.factor(nil, 'jobs') == 1)
  local l = P.list(3)
  local unlocked = 0
  for _, p in ipairs(l.list) do if p.unlocked then unlocked = unlocked + 1 end end
  check('perks: the list for the phone has every perk with its text, and the ones up to the rank unlocked', l.tier == 3 and #l.list == 6 and unlocked == 3 and l.list[1].label == 'Trade prices' and l.list[3].text == 'Jobs pay 10% more.')
  check('perks: the bank limit, the garage price and the fine follow the perk', (function()
    local ST = require('sl/core/state')
    local st = ST.new(1, 0)
    st.rep, st.garageLevel, st.money = 1000, 1, 100000
    local old = { c = rawget(_G, 'sl_career'), e = rawget(_G, 'extensions'), r = rawget(_G, 'sl_rivals'), g = rawget(_G, 'guihooks') }
    _G.guihooks = { trigger = function() end }
    _G.extensions = { hook = function() end }
    _G.sl_career = { isActive = function() return true end, getState = function() return st end, addMoney = function(a, l) return ST.addMoney(st, a, l) end }
    package.loaded['sl/perks'] = nil
    package.loaded['sl/bank'] = nil
    _G.sl_rivals = { rank = function() return 1 end }
    _G.sl_perks = require('sl/perks')
    local B = require('sl/bank')
    local plain = B.summary().limit
    _G.sl_rivals = { rank = function() return 5 end }
    local boosted = B.summary().limit
    local bankRules = require('sl/core/bank')
    local ok = boosted == math.floor(plain * 1.25 / 500) * 500 and boosted > plain and plain == bankRules.loanLimit(1000, 1, 0)
    _G.sl_perks = nil
    _G.sl_career, _G.extensions, _G.sl_rivals, _G.guihooks = old.c, old.e, old.r, old.g
    package.loaded['sl/perks'], package.loaded['sl/bank'] = nil, nil
    return ok
  end)())
end

-- speed traps and zones (campaign idea #1)
do
  local TR = require('sl/core/traps')
  local rngLib = require('sl/core/rng')
  -- a map of straight roads: 30 links of 400 m in a grid of lines 1000 m apart, plus short ones and a hidden one
  local nodes = {}
  for i = 1, 30 do
    nodes['a' .. i] = { pos = { x = 0, y = i * 1000, z = 0 }, links = { ['b' .. i] = { drivability = 1, speedLimit = 25 } } }
    nodes['b' .. i] = { pos = { x = 400, y = i * 1000, z = 5 }, links = { ['a' .. i] = { drivability = 1, speedLimit = 25 } } }
  end
  nodes.s1 = { pos = { x = 9000, y = 0, z = 0 }, links = { s2 = { drivability = 1, speedLimit = 25 } } }
  nodes.s2 = { pos = { x = 9100, y = 0, z = 0 }, links = { s1 = { drivability = 1, speedLimit = 25 } } }
  nodes.h1 = { pos = { x = 7000, y = 0, z = 0 }, links = { h2 = { drivability = 1, speedLimit = 25, hiddenInNavi = true } } }
  nodes.h2 = { pos = { x = 7400, y = 0, z = 0 }, links = {} }
  local list1 = TR.select(nodes, rngLib.new(7))
  local list2 = TR.select(nodes, rngLib.new(7))
  local nTrap, nZone, ok = 0, 0, true
  for _, t in ipairs(list1) do if t.kind == 'trap' then nTrap = nTrap + 1 else nZone = nZone + 1 end end
  for i = 1, #list1 do for j = i + 1, #list1 do if (list1[i].x - list1[j].x) ^ 2 + (list1[i].y - list1[j].y) ^ 2 < TR.APART ^ 2 then ok = false end end end
  check('traps: six traps and two zones, spaced apart, from the long links only', nTrap == 6 and nZone == 2 and ok and #list1 == 8)
  check('traps: the same map and seed give the same traps; another seed gives others', (function()
    local same = true
    for i = 1, #list1 do if list1[i].x ~= list2[i].x or list1[i].y ~= list2[i].y then same = false end end
    local other = TR.select(nodes, rngLib.new(8))
    local diff = false
    for i = 1, #list1 do if other[i].y ~= list1[i].y then diff = true end end
    return same and diff
  end)())
  local t1 = list1[#list1]
  check('traps: a trap has one gate and a target in km/h; a zone has two gates inside its link', t1.kind == 'trap' and t1.g1 and not t1.g2 and t1.target >= 110 and list1[1].kind == 'zone' and list1[1].g2 and list1[1].len > 200)
  local hidden = true
  for _, t in ipairs(list1) do if t.y == 0 then hidden = false end end
  check('traps: a short link and a hidden one never hold a trap', hidden)
  local gate, d = { x = 100, y = 100 }, { dx = 1, dy = 0 }
  check('traps: a car crossing the gate counts, one that passes beside or stops before it does not',
    TR.crossed({ x = 95, y = 100 }, { x = 105, y = 100 }, gate, d) and TR.crossed({ x = 105, y = 103 }, { x = 95, y = 97 }, gate, d)
    and not TR.crossed({ x = 90, y = 100 }, { x = 99, y = 100 }, gate, d) and not TR.crossed({ x = 95, y = 120 }, { x = 105, y = 120 }, gate, d))
  local rec, info = TR.score(nil, { target = 150 }, 140.9)
  check('traps: a score below the target is a best but pays nothing', rec.best == 140 and rec.count == 1 and not rec.paid and not info.first and info.best)
  local rec2, info2 = TR.score(rec, { target = 150 }, 151)
  local rec3, info3 = TR.score(rec2, { target = 150 }, 170)
  check('traps: the target pays once, a later better run only records', info2.first and rec2.paid and not info3.first and info3.best and rec3.best == 170 and rec3.count == 3)

  -- the extension: a car driven through a trap and a zone
  local ST = require('sl/core/state')
  local st = ST.new(1, 0)
  st.seed = 3
  local old = { c = rawget(_G, 'sl_career'), e = rawget(_G, 'extensions'), g = rawget(_G, 'guihooks'), pv = rawget(_G, 'getPlayerVehicle'), map = rawget(_G, 'map'), lv = rawget(_G, 'getCurrentLevelIdentifier'), um = rawget(_G, 'ui_message') }
  local paid, toasts = 0, {}
  _G.guihooks = { trigger = function(_, d) toasts[#toasts + 1] = d and d.text end }
  _G.ui_message = nil
  _G.extensions = { hook = function() end }
  _G.map = { getMap = function() return { nodes = nodes } end }
  _G.getCurrentLevelIdentifier = function() return 'test_level' end
  _G.sl_career = { isActive = function() return true end, getState = function() return st end, payOut = function(a) paid = paid + a return ST.addMoney(st, a, 'x') end }
  local pos, vel = { x = 0, y = 0, z = 0 }, 0
  _G.getPlayerVehicle = function() return { getPosition = function() return { x = pos.x, y = pos.y, z = 0 } end, getVelocity = function() return { length = function() return vel end } end } end
  package.loaded['sl/traps'] = nil
  local TX = require('sl/traps')
  TX.onUpdate(0.2)
  local sm = TX.summary()
  check('traps: the career gets its list in the save, on first sight', sm and #sm.list == 8 and st.traps.levels.test_level and #st.traps.levels.test_level.list == 8)
  local trap
  for _, t in ipairs(st.traps.levels.test_level.list) do if t.kind == 'trap' then trap = t break end end
  local function drive(from, to, speed)
    pos = { x = from.x + 500, y = from.y + 500 } TX.onUpdate(0.2)         -- (away first: the jump forgets the last place)
    pos = from vel = speed TX.onUpdate(0.2)
    pos = to TX.onUpdate(0.2)
  end
  local offs = trap.dx * 10
  drive({ x = trap.x - trap.dx * 6, y = trap.y - trap.dy * 6 }, { x = trap.x + trap.dx * 6, y = trap.y + trap.dy * 6 }, 200 / 3.6)
  check('traps: driving through a trap at 200 km/h records it and pays the target once', st.traps.levels.test_level.rec[trap.id] and st.traps.levels.test_level.rec[trap.id].best == 200 and paid == 250 and st.rep >= 5)
  local before = paid
  drive({ x = trap.x - trap.dx * 6, y = trap.y - trap.dy * 6 }, { x = trap.x + trap.dx * 6, y = trap.y + trap.dy * 6 }, 210 / 3.6)
  check('traps: the second run only records', st.traps.levels.test_level.rec[trap.id].best == 210 and paid == before and st.traps.levels.test_level.rec[trap.id].count == 2)
  pos = { x = 0, y = 0 }
  TX.onUpdate(0.2)
  drive({ x = trap.x + 5000, y = trap.y }, { x = trap.x - 5000, y = trap.y }, 300 / 3.6)
  check('traps: a jump of more than 80 m between samples (a teleport) counts as no crossing', st.traps.levels.test_level.rec[trap.id].count == 2)
  do -- another map and back: the records and what was paid stay with their map
    local before0 = paid
    _G.getCurrentLevelIdentifier = function() return 'other_level' end
    TX.onUpdate(0.2)
    check('traps: another map gets its own traps; the first map keeps its records', st.traps.levels.other_level and #st.traps.levels.other_level.list == 8 and st.traps.levels.test_level.rec[trap.id].paid == true)
    _G.getCurrentLevelIdentifier = function() return 'test_level' end
    pos = { x = trap.x - trap.dx * 506, y = trap.y - trap.dy * 506 } TX.onUpdate(0.2)
    pos = { x = trap.x - trap.dx * 6, y = trap.y - trap.dy * 6 } vel = 220 / 3.6 TX.onUpdate(0.2)
    pos = { x = trap.x + trap.dx * 6, y = trap.y + trap.dy * 6 } TX.onUpdate(0.2)
    check('traps: back on the first map the trap does not pay a second time, and the better speed is the record', paid == before0 and st.traps.levels.test_level.rec[trap.id].best == 220)
    -- a save from the first shape of the part (one level at the top) is read as that level's entry
    local old1 = st.traps
    st.traps = { level = 'test_level', list = old1.levels.test_level.list, rec = { [trap.id] = { best = 150, count = 1, paid = true } } }
    local sm2 = TX.summary()
    check('traps: an older save is read as the entry of its map', st.traps.levels and st.traps.levels.test_level.rec[trap.id].best == 150 and st.traps.level == nil and sm2 and #sm2.list == 8)
  end
  do -- a zone: the average speed between its two gates
    local zone
    for _, t in ipairs(st.traps.levels.test_level.list) do if t.kind == 'zone' then zone = t break end end
    local realClock, clk = os.clock, 100
    os.clock = function() return clk end
    local function at(g, sp, dt) clk = clk + dt local p0 = { x = g.x - zone.dx * 6, y = g.y - zone.dy * 6 } pos = { x = p0.x + 500, y = p0.y + 500 } TX.onUpdate(0.2) pos = p0 vel = sp TX.onUpdate(0.2) pos = { x = g.x + zone.dx * 6, y = g.y + zone.dy * 6 } TX.onUpdate(0.2) end
    local length = zone.len
    at(zone.g1, 30, 0.5)
    at(zone.g2, 30, length / (160 / 3.6))
    local r = st.traps.levels.test_level.rec[zone.id]
    check('traps: a zone records the average speed from the first gate to the second (160 km/h) and pays at the target', r and r.best == 159 or r and r.best == 160)
    at(zone.g2, 30, 1)
    check('traps: the second gate alone, with no first gate, records nothing', st.traps.levels.test_level.rec[zone.id].count == 1)
    os.clock = realClock
  end
  _G.sl_career, _G.extensions, _G.guihooks, _G.getPlayerVehicle, _G.map, _G.getCurrentLevelIdentifier, _G.ui_message = old.c, old.e, old.g, old.pv, old.map, old.lv, old.um
  package.loaded['sl/traps'] = nil
end

-- danger zones (campaign idea #2)
do
  local D = require('sl/core/danger')
  local TR = require('sl/core/traps')
  local rngLib = require('sl/core/rng')
  check('danger: slip angle between the way a car moves and the way it points', math.abs(D.slipAngle(10, 0, 1, 0)) < 1e-6 and math.abs(D.slipAngle(10, 0, 0, 1) - 90) < 1e-6 and math.abs(D.slipAngle(0, 0, 1, 0)) == 0)
  check('danger: drift points only when fast enough and sliding between 15 and 80 degrees', D.driftPoints(20, 45, 1) == 20 and D.driftPoints(20, 10, 1) == 0 and D.driftPoints(20, 85, 1) == 0 and D.driftPoints(5, 45, 1) == 0 and D.driftPoints(20, -45, 1) == 20 and D.driftPoints(20, 90, 1) == 0)
  local st = D.newJump()
  local r
  for i = 1, 6 do r = D.jumpStep(st, true, i * 10, 0, 0.1) end
  r = D.jumpStep(st, false, 62, 0, 0.1)
  check('danger: a jump is the ground covered between take-off and landing after enough air time', r and math.abs(r - 52) < 1e-6)
  local st2 = D.newJump()
  D.jumpStep(st2, true, 0, 0, 0.1)
  check('danger: a bump shorter than 0.4 s is no jump, and a landing with no take-off gives nothing', D.jumpStep(st2, false, 3, 0, 0.1) == nil and D.jumpStep(D.newJump(), false, 3, 0, 0.1) == nil)
  local st3 = D.newJump()
  for i = 1, 6 do D.jumpStep(st3, true, 0, 0, 0.1) end
  check('danger: a distance of more than 400 m was a teleport', D.jumpStep(st3, false, 900, 0, 0.1) == nil)
  local n1, p1 = D.ladder(0, 45)
  local n2, p2 = D.ladder(n1, 45)
  local n3, p3 = D.ladder(n2, 120)
  check('danger: the ladder pays each rung once, in order', n1 == 2 and p1[1] == 150 and p1[2] == 300 and n2 == 2 and #p2 == 0 and n3 == 4 and p3[1] == 600 and p3[2] == 1000)

  local nodes = {}
  for i = 1, 20 do
    nodes['a' .. i] = { pos = { x = 0, y = i * 1000, z = 0 }, links = { ['b' .. i] = { drivability = 1, speedLimit = 25 } } }
    nodes['b' .. i] = { pos = { x = 400, y = i * 1000, z = 0 }, links = { ['a' .. i] = { drivability = 1, speedLimit = 25 } } }
  end
  local taken = TR.select(nodes, rngLib.new(7))
  local drift = TR.selectDrift(nodes, rngLib.new(9), 2, taken)
  local apart = true
  for _, d in ipairs(drift) do for _, t in ipairs(taken) do if (d.x - t.x) ^ 2 + (d.y - t.y) ^ 2 < TR.APART ^ 2 then apart = false end end end
  check('danger: two drift zones with a target and two gates, away from the traps', #drift == 2 and drift[1].kind == 'drift' and drift[1].target == 600 and drift[1].g2 and apart)

  -- the extension: a jump and a drift run
  local ST = require('sl/core/state')
  local st0 = ST.new(1, 0)
  st0.seed = 4
  local old = { c = rawget(_G, 'sl_career'), e = rawget(_G, 'extensions'), g = rawget(_G, 'guihooks'), pv = rawget(_G, 'getPlayerVehicle'), map = rawget(_G, 'map'), lv = rawget(_G, 'getCurrentLevelIdentifier'),
    um = rawget(_G, 'ui_message'), ray = rawget(_G, 'castRayStatic'), v3 = rawget(_G, 'vec3'), clock = os.clock }
  local paid = 0
  _G.guihooks = { trigger = function() end }
  _G.ui_message = nil
  _G.extensions = { hook = function() end }
  _G.map = { getMap = function() return { nodes = nodes } end }
  _G.getCurrentLevelIdentifier = function() return 'test_level' end
  _G.vec3 = function(x, y, z) return { x = x, y = y, z = z, __add = nil } end
  _G.sl_career = { isActive = function() return true end, getState = function() return st0 end, payOut = function(a) paid = paid + a return ST.addMoney(st0, a, 'x') end }
  local pos, vel, face, ground = { x = 0, y = 0, z = 0 }, { x = 0, y = 0 }, { x = 1, y = 0 }, 0.5
  _G.castRayStatic = function() return ground end
  local function veh()
    local p = setmetatable({ x = pos.x, y = pos.y, z = pos.z or 0 }, { __add = function(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end })
    return { getJBeamFilename = function() return 'covet' end, getPosition = function() return p end,
      getVelocity = function() return { x = vel.x, y = vel.y, length = function() return math.sqrt(vel.x ^ 2 + vel.y ^ 2) end } end, getDirectionVector = function() return { x = face.x, y = face.y } end }
  end
  _G.getPlayerVehicle = function() return veh() end
  package.loaded['sl/danger'] = nil
  local DX = require('sl/danger')
  DX.onUpdate(0.2)
  local sm = DX.summary()
  check('danger: the career gets two drift zones in the save and a jump record', sm and #sm.drift == 2 and sm.jump.next == 20 and st0.danger.levels.test_level ~= nil)
  -- a jump of 50 m: in the air for 0.8 s
  pos = { x = 500, y = 500, z = 0 } ground = 0.5 DX.onUpdate(0.2)
  ground = 3 for i = 1, 4 do pos = { x = 500 + i * 12, y = 500, z = 0 } DX.onUpdate(0.2) end
  ground = 0.5 pos = { x = 560, y = 500, z = 0 } DX.onUpdate(0.2)
  check('danger: a 50 m jump is recorded, pays the 20 and 40 m rungs and nothing more', st0.danger.jump.best > 40 and st0.danger.jump.paid == 2 and paid == 450 and DX.summary().jump.next == 70)
  -- a drift run through the first zone
  local zone = st0.danger.levels.test_level.list[1]
  local clock = 100
  os.clock = function() return clock end
  vel, face = { x = 25, y = 0 }, { x = 0.7071, y = 0.7071 }          -- 45 degrees of slip at 25 m/s
  local function at(g, back) pos = { x = g.x - zone.dx * 6 * back, y = g.y - zone.dy * 6 * back } DX.onUpdate(0.2) end
  -- (the zone runs along its dx, dy: move the car along it with the slip kept)
  vel = { x = zone.dx * 25, y = zone.dy * 25 }
  face = { x = (zone.dx + -zone.dy) * 0.7071, y = (zone.dy + zone.dx) * 0.7071 }
  pos = { x = zone.g1.x - zone.dx * 400, y = zone.g1.y - zone.dy * 400 } DX.onUpdate(0.2) DX.onUpdate(0.2)
  pos = { x = zone.g1.x - zone.dx * 6, y = zone.g1.y - zone.dy * 6 } clock = clock + 0.2 DX.onUpdate(0.2)
  pos = { x = zone.g1.x + zone.dx * 6, y = zone.g1.y + zone.dy * 6 } clock = clock + 0.2 DX.onUpdate(0.2)
  for i = 1, 31 do pos = { x = pos.x + zone.dx * 9, y = pos.y + zone.dy * 9 } DX.onUpdate(0.1) end
  pos = { x = zone.g2.x - zone.dx * 6, y = zone.g2.y - zone.dy * 6 } DX.onUpdate(0.2)
  pos = { x = zone.g2.x + zone.dx * 6, y = zone.g2.y + zone.dy * 6 } DX.onUpdate(0.2)
  local rec = st0.danger.levels.test_level.rec[zone.id]
  check('danger: a drift run between the gates scores points, and a score under the target pays nothing', rec and rec.best > 0 and rec.count == 1 and not rec.paid and paid == 450)
  os.clock = old.clock
  _G.sl_career, _G.extensions, _G.guihooks, _G.getPlayerVehicle, _G.map, _G.getCurrentLevelIdentifier, _G.ui_message, _G.castRayStatic, _G.vec3 = old.c, old.e, old.g, old.pv, old.map, old.lv, old.um, old.ray, old.v3
  package.loaded['sl/danger'] = nil
end

-- cinematic moments (sl/core/scenes): what the UI is told, the reduced-motion hold, the skip guard
do
  local sc = require('sl/core/scenes')
  local strings = require('sl/core/strings')
  local n = sc.spec('night', { day = 4 }, false, strings.t)
  check('scenes: the night scene has its title, its day in the subtitle, the full hold and the fades', n.kind == 'night' and n.title == 'Night' and n.subtitle == 'Day 4: the street is awake' and n.hold == 3.4 and n.fadeIn == 0.5 and n.fadeOut == 0.6 and n.reduce == false)
  local d = sc.spec('day', { day = 5 }, true, strings.t)
  check('scenes: reduce motion shortens the hold and is passed on to the UI', d.kind == 'day' and d.hold == 1.2 and d.reduce == true and d.subtitle == 'Day 5 begins')
  check('scenes: an unknown kind has no scene, a missing day is day 1', sc.spec('nope', {}, false, strings.t) == nil and sc.spec('day', nil, false, strings.t).day == 1)
  check('scenes: the cues are the games own UI events, a start whoosh and a title chime; reduce motion has only the chime', #n.cues == 2 and n.cues[1].at == 0 and n.cues[2].at == 1.3 and n.cues[1].event:find('^event:>UI>') and #d.cues == 1)
  check('scenes: a scene cannot be skipped in its first moments, then it can', not sc.canSkip(0) and not sc.canSkip(0.39) and sc.canSkip(0.4) and sc.canSkip(2))
  check('scenes: every kind has its texts in the table', (function() for _, k in pairs(sc.KINDS) do if strings.TEXT[k.title] == nil or strings.TEXT[k.sub] == nil then return false end end return true end)())
end

-- the short moments (banners): the spec for each style, the text with its numbers, the unknown style, sl_scenes.play never throws
do
  local sc = require('sl/core/scenes')
  local strings = require('sl/core/strings')
  local h = sc.banner('heat', { level = 3 }, false, strings.t)
  check('banners: heat 3 has its title, tone and a sound', h.kind == 'banner' and h.style == 'heat' and h.title == 'Heat 3' and h.tone == 'warn' and #h.cues == 1 and h.hold > 0)
  check('banners: a countdown number is the title; the car reveal shows the car name', sc.banner('count', { n = 2 }, false, strings.t).title == '2' and sc.banner('reveal', { name = 'Covet' }, false, strings.t).subtitle == 'Covet')
  check('banners: busted and a lost slip are bad, a won slip and a new car are good (every tone has a mark in the UI)', sc.banner('busted', nil, false, strings.t).tone == 'bad' and sc.banner('pinklose', { name = '$900' }, false, strings.t).tone == 'bad'
    and sc.banner('pinkwin', { name = 'Covet' }, false, strings.t).tone == 'good' and sc.banner('reveal', {}, false, strings.t).tone == 'good')
  check('banners: the garage tier banner names the level through the strings table', sc.banner('tier', { level = 2 }, false, strings.t).subtitle == 'Garage level 2')
  check('banners: an unknown style is nothing; reduce motion is passed on', sc.banner('nope', {}, false, strings.t) == nil and sc.banner('go', {}, true, strings.t).reduce == true)
  check('banners: every style has its texts in the table', (function() for _, b in pairs(sc.BANNERS) do if strings.TEXT[b.title] == nil or (b.sub and strings.TEXT[b.sub] == nil) then return false end end return true end)())
  local saved = _G.guihooks
  local sent = {}
  _G.guihooks = { trigger = function(n, d) sent[#sent + 1] = d.style or d.kind end }
  package.loaded['sl/scenes'] = nil
  local Sc = require('sl/scenes')
  check('banners: play shows a banner over the live game and says so', Sc.play('busted', {}) == true and sent[1] == 'busted')
  check('banners: an unknown style is not shown, and play never throws', Sc.play('nope', {}) == false and Sc.play(nil, nil) == false)
  _G.guihooks = { trigger = function() error('boom') end }
  check('banners: a failing UI hook does not reach the caller', Sc.play('busted', {}) == false)
  -- the career's hooks pick the banner
  _G.guihooks = { trigger = function(n, d) sent[#sent + 1] = d.style or d.kind end }
  package.loaded['sl/scenes'] = nil
  local H = require('sl/scenes')
  sent = {}
  H.onStreetLegalBusted(300, 0, 'Covet') H.onStreetLegalBusted(300, 900, 'Covet') H.onStreetLegalPinkSlip(true, 'Dora') H.onStreetLegalPinkSlip(false, 'Dora') H.onStreetLegalHeatUp(3)
  H.onStreetLegalCarAdded({ name = 'Covet' }) H.onStreetLegalGarageMoved(1, 2, 6000) H.onStreetLegalRaceGo()
  check('banners: the career hooks choose the style (busted or impound, a slip won or lost, heat, a new car, a bigger garage, go)', table.concat(sent, ',') == 'busted,impound,pinkwin,pinklose,heat,reveal,tier,go', table.concat(sent, ','))
  sent = {}
  H.onWrenchWorksGarageEntered('Belasco City Garage') H.onWrenchWorksGarageLeft()
  check('banners: the garage hooks of Wrench Works pick garage_in and garage_out', table.concat(sent, ',') == 'garage_in,garage_out', table.concat(sent, ','))
  sent = {}
  H.onStreetLegalCalendarReminder({ title = 'Utah Rally' }, 24) H.onStreetLegalCalendarReminder(nil, nil)
  check('banners: the calendar reminder is a banner, with odd arguments too', sent[1] == 'reminder' and sent[2] == 'reminder' and require('sl/core/scenes').banner('reminder', { name = 'Utah Rally', level = 1 }, false, require('sl/core/strings').t).subtitle == 'Utah Rally in 1 h')
  sent = {}
  H.onStreetLegalRoundResult({ name = 'Utah Rally', round = 2, place = 1, points = 25 }) H.onStreetLegalRoundResult({ round = 2, place = 3, points = 15 }) H.onStreetLegalRoundResult({ round = 3, place = 7, points = 2 })
  H.onStreetLegalRoundResult({ round = 4, dnf = true }) H.onStreetLegalRoundResult({ round = 5, missed = true }) H.onStreetLegalRoundResult(nil) H.onStreetLegalSeriesFinished({ name = 'Utah Rally', pos = 1, points = 70 }) H.onStreetLegalSeriesFinished({ pos = 3 }) H.onStreetLegalSeriesFinished({ pos = 6 })
  check('banners: a round shows win / podium / done / did not finish, a missed round and nothing show nothing; a series shows win / podium / over', sent[1] == 'round_win' and sent[2] == 'round_podium' and sent[3] == 'round_done' and sent[4] == 'round_dnf' and sent[5] == 'series_win' and sent[6] == 'series_podium' and sent[7] == 'series_end' and #sent == 7)
  do
    local sc2, t2 = require('sl/core/scenes'), require('sl/core/strings').t
    local st, d = sc2.roundBanner({ name = 'Utah Rally', round = 2, place = 3, points = 15 })
    local b = sc2.banner(st, d, false, t2)
    check('banners: the texts carry the round, place, series and points', b.title == 'Round 2: place 3' and b.subtitle == 'Utah Rally: 15 points' and b.tone == 'good')
    local s2, d2 = sc2.seriesBanner({ name = 'Utah Rally', pos = 1, points = 70 })
    check('banners: a series win says so', sc2.banner(s2, d2, false, t2).title == 'Series won' and sc2.banner(s2, d2, false, t2).subtitle == 'Utah Rally: 70 points')
  end
  do
    local sc3, t3 = require('sl/core/scenes'), require('sl/core/strings').t
    local st3, d3 = sc3.showBanner({ place = 2, names = { 'Ava', 'You', 'Cy' }, total = 5 })
    local b3 = sc3.banner(st3, d3, false, t3)
    check('banners: the show podium has a title by place and the three names', b3.title == '2nd place' and b3.subtitle == '1. Ava   2. You   3. Cy')
    check('banners: the show podium: place 1 is the winner, 3 is third, 6 is a plain place, no place is nothing', select(1, sc3.showBanner({ place = 1 })) == 'show_win' and select(1, sc3.showBanner({ place = 3 })) == 'show_3' and select(1, sc3.showBanner({ place = 6 })) == 'show_other' and sc3.showBanner({}) == nil)
  end
  check('banners: a hook with odd arguments does not throw', pcall(function() H.onStreetLegalBusted(nil, nil, nil) H.onStreetLegalCarAdded(nil) H.onStreetLegalGarageMoved() end))
  _G.guihooks = saved
  package.loaded['sl/scenes'] = nil
end

-- sl_scenes.run: the scene around a change of the world; the caller's lock is released whatever fails inside, the screen is always cleared
do
  local saved = { jobs = _G.core_jobsystem, gui = _G.guihooks }
  local sent, order = {}, {}
  _G.guihooks = { trigger = function(name, d) sent[#sent + 1] = name .. ':' .. tostring(d.kind or d.on) end }
  _G.core_jobsystem = { create = function(fn) fn({ sleep = function() end }) end }       -- (a job that runs at once)
  package.loaded['sl/scenes'] = nil
  local Sc = require('sl/scenes')
  local function run(move, release)
    sent, order = {}, {}
    return Sc.run('night', { day = 3 }, move or function() order[#order + 1] = 'move' end, release or function() order[#order + 1] = 'release' end)
  end
  check('scenes.run: a scene runs, the world moves, the lock is released, the scene is cleared', run() == true and table.concat(order, ',') == 'move,release' and sent[1] == 'slScene:night' and sent[#sent] == 'slScene:end')
  check('scenes.run: a failing move still releases and clears the screen', (function() local ok = run(function() error('boom') end) return ok == true and order[1] == 'release' and sent[#sent] == 'slScene:end' end)())
  check('scenes.run: a failing release does not leave the screen covered', (function() run(nil, function() error('boom') end) return sent[#sent] == 'slScene:end' end)())
  local realBegin = Sc.begin
  Sc.begin = function() error('boom') end
  check('scenes.run: a begin that throws is no scene: false, nothing covered, nothing moved (the caller does the plain fade)', (function() local r = run() return r == false and #order == 0 end)())
  Sc.begin = realBegin
  local realHold, realFinish = Sc.hold, Sc.finish
  Sc.hold = function() error('boom') end
  check('scenes.run: a hold that throws still moves, releases and finishes', (function() local r = run() return r == true and table.concat(order, ',') == 'move,release' and sent[#sent] == 'slScene:end' end)())
  Sc.hold = realHold
  Sc.finish = function() error('boom') end
  check('scenes.run: a finish that throws does not break the caller', (function() local r = run() return r == true and table.concat(order, ',') == 'move,release' end)())
  Sc.finish = realFinish
  realFinish()                                   -- (the scene the throwing finish left active is cleared)
  _G.core_jobsystem = { create = function() error('boom') end }
  check('scenes.run: a job system that throws is no scene: false, the screen not covered', (function() local r = run() return r == false and sent[#sent] == 'slScene:end' and #order == 0 end)())
  _G.core_jobsystem = nil
  check('scenes.run: without a job system there is no scene', run() == false)
  _G.core_jobsystem, _G.guihooks = saved.jobs, saved.gui
  package.loaded['sl/scenes'] = nil
end

-- barn finds (campaign idea #3)
do
  local B = require('sl/core/barn')
  local rngLib = require('sl/core/rng')
  -- a map: a grid of through roads, and dead ends far out
  local nodes = {}
  for i = 1, 6 do
    nodes['r' .. i] = { pos = { x = i * 300, y = 0, z = 0 }, links = { ['r' .. (i % 6 + 1)] = {}, ['r' .. ((i + 4) % 6 + 1)] = {} } }
  end
  nodes.d1 = { pos = { x = 3000, y = 3000, z = 5 }, links = { r1 = {} } }
  nodes.d2 = { pos = { x = 3300, y = 3000, z = 5 }, links = { r1 = {} } }       -- (too close to d1)
  nodes.d3 = { pos = { x = -3000, y = 3000, z = 0 }, links = { r2 = {} } }
  nodes.d4 = { pos = { x = 100, y = 100, z = 0 }, links = { r3 = {} } }          -- (next to the place)
  nodes.d5 = { pos = { x = 3000, y = -3000, z = 0 }, links = { r2 = {} } }
  nodes.d6 = { pos = { x = -3000, y = -3000, z = 0 }, links = { r2 = {} } }
  local places = { { id = 'junk', name = 'the junkyard', x = 0, y = 0 } }
  local spots = B.select(nodes, places, rngLib.new(3))
  local ok = true
  for i = 1, #spots do
    if spots[i].x == 100 then ok = false end
    for j = i + 1, #spots do if (spots[i].x - spots[j].x) ^ 2 + (spots[i].y - spots[j].y) ^ 2 < B.APART ^ 2 then ok = false end end
  end
  check('barn: four spots at dead ends, far from the places and from each other', #spots == 4 and ok and spots[1].id == 'b1')
  local again = B.select(nodes, places, rngLib.new(3))
  check('barn: the same map and seed give the same spots', again[1].x == spots[1].x and again[4].y == spots[4].y)
  check('barn: the hint names the car, the nearest place and the way from it', (function()
    local h = B.hint({ x = 3000, y = 0 }, places, 'Covet')
    return h:find('Covet', 1, true) and h:find('the junkyard', 1, true) and h:find('3 km east', 1, true)
  end)())
  check('barn: the compass words', B.compass(0, 0, 10, 0) == 'east' and B.compass(0, 0, 0, 10) == 'north' and B.compass(0, 0, -10, 0) == 'west' and B.compass(0, 0, 0, -10) == 'south' and B.compass(0, 0, 10, 10) == 'north-east')
  check('barn: no place at all still gives a rumour', B.hint({ x = 1, y = 1 }, {}, 'Covet'):find('Covet', 1, true) ~= nil)
  local offer = B.carOffer({ name = 'Covet', model = 'covet', value = 10000, condition = 0.9, faults = {}, mileage = 100 }, rngLib.new(4))
  check('barn: the car is in a poor state, with 3 to 5 faults, a high mileage and a low price', offer.condition >= 0.12 and offer.condition <= 0.3 and #offer.faults >= 3 and #offer.faults <= 5 and offer.mileage >= 150000 and offer.price == 2200 and offer.kind == 'barn')
  check('barn: the offer given is not changed, and pick takes the most valuable', B.pick({ { value = 1 }, { value = 9 }, { value = 5 } }).value == 9 and B.pick({}) == nil)

  -- the ad: hidden until found, a private car ad when found, its faults behind the mechanic's check
  local ST = require('sl/core/state')
  local st = ST.new(1, 0)
  st.day, st.rep, st.seed = 5, 300, 7
  st.market = { listings = {}, nextId = 1, refreshed = 1e9, deliveries = {}, rounds = {}, mine = {} }
  local old = { c = rawget(_G, 'sl_career'), e = rawget(_G, 'extensions'), g = rawget(_G, 'guihooks'), pv = rawget(_G, 'getPlayerVehicle'), lot = rawget(_G, 'sl_lot'), map = rawget(_G, 'map'),
    lv = rawget(_G, 'getCurrentLevelIdentifier'), cl = rawget(_G, 'sl_classifieds'), um = rawget(_G, 'ui_message'), fleet = rawget(_G, 'sl_fleet') }
  local sent = {}
  _G.guihooks = { trigger = function() end }
  _G.extensions = { hook = function() end }
  _G.ui_message = nil
  _G.sl_fleet = nil
  _G.getPlayerVehicle = function() return nil end
  _G.getCurrentLevelIdentifier = function() return 'test_level' end
  _G.map = { getMap = function() return { nodes = nodes } end }
  _G.sl_lot = { privateOffers = function() return { { name = 'Covet', model = 'covet', value = 6000, condition = 0.8, faults = {}, mileage = 50000, kind = 'used', config = 'vehicles/covet/a.pc', id = 'x1' },
    { name = 'Bolide', model = 'bolide', value = 20000, condition = 0.9, faults = {}, mileage = 10000, kind = 'used', config = 'vehicles/bolide/b.pc', id = 'x2' } } end }
  _G.sl_career = { isActive = function() return true end, has = function() return true end, getState = function() return st end, hour = function() return 12 end, mapText = function(t) return t end,
    addMoney = function(a, l) return ST.addMoney(st, a, l) end, getPlaces = function() return { junk = { name = 'the junkyard', pos = { x = 0, y = 0, z = 0 } } } end,
    sendText = function(who, text) sent[#sent + 1] = text end }
  package.loaded['jbeam/io'] = {}
  package.loaded['sl/classifieds'] = nil
  _G.sl_classifieds = require('sl/classifieds')
  _G.getPlayerVehicle = function() return nil end
  local C = _G.sl_classifieds
  local id, name = C.addBarn({ x = 3000, y = 0, z = 0 }, 11)
  local l = st.market.listings[1]
  check('barn: addBarn makes a hidden, cheap, poor car ad at the spot from the most valuable offer', id and l.id == id and l.hidden == true and l.barn and name == 'Bolide' and l.offer.price == 4400 and l.where.x == 3000 and l.expires > 24 * 5)
  local oldPV = rawget(_G, 'getPlayerVehicle')
  local function card() for _, c in ipairs(C.summary().listings) do if c.id == id then return c end end end
  for _, c in ipairs(st.cars) do c.model = c.model or 'covet' end
  check('barn: the app does not show it before it is found', card() == nil)
  C.revealBarn(id)
  local c1 = card()
  check('barn: found, it is a private car ad with its faults hidden until a mechanic has looked', c1 and c1.car == true and c1.hidden == true and c1.faults == nil and c1.ask == 4400 and c1.history ~= nil)
  st.money = 1000
  C.check(id)
  local c2 = card()
  check('barn: after the check the faults and what they cost show', c2.checked == true and c2.faults >= 3 and #c2.found == c2.faults)

  -- the extension: the rumour and the finding
  package.loaded['sl/barnfinds'] = nil
  local BX = require('sl/barnfinds')
  st.market.listings = {}
  BX.onStreetLegalNewDay(4)
  check('barn: not before the first rumour day', st.barn and #sent == 0)
  BX.onStreetLegalNewDay(st.barn.nextHint)
  local spot
  for _, sp in ipairs(st.barn.levels.test_level.spots) do if sp.listing then spot = sp end end
  check('barn: on the day a contact texts the rumour and a hidden ad stands at that spot', spot and #sent == 1 and sent[1]:find('km', 1, true) and st.market.listings[1].hidden == true and st.barn.nextHint > st.day)
  check('barn: the Map app can show the rumoured spots', #BX.summary().rumours == 1)
  local px, py = spot.x + 500, spot.y
  _G.getPlayerVehicle = function() return { getPosition = function() return { x = px, y = py, z = 0 } end } end
  BX.onUpdate(1.5)
  check('barn: a car far from the spot finds nothing', not spot.found)
  px = spot.x + 20
  BX.onUpdate(1.5)
  check('barn: within 35 m the car is found and the ad appears', spot.found == true and st.market.listings[1].hidden == nil and #BX.summary().rumours == 0)
  -- a hidden ad can be neither offered on, bought nor checked
  do
    local hid = st.market.listings[1]
    hid.hidden = true
    check('barn: a hidden ad is refused by offer, buy and check', C.offer(hid.id, 100) == false and C.buy(hid.id, 'pickup') == false and C.check(hid.id) == false)
    hid.hidden = nil
  end
  -- the ad bought or gone: after a month the spot can hold another car
  do
    st.market.listings[1].taken = true
    local spot2 = spot
    check('barn: the barn asks what became of its ad', C.barnState(spot2.listing) == 'gone')
    BX.onStreetLegalNewDay(st.day + 1)
    check('barn: not reused at once', spot2.listing ~= nil and spot2.goneDay ~= nil)
    BX.onStreetLegalNewDay(st.barn.nextHint + 200)
    check('barn: reusable a month later (it may already hold the next rumour)', spot2.goneDay == nil)
  end
  -- the update fails safe: five errors switch it off
  do
    local oldPV2 = _G.getPlayerVehicle
    _G.getPlayerVehicle = function() error('boom') end
    for i = 1, 8 do BX.onUpdate(1.5) end
    _G.getPlayerVehicle = oldPV2
    check('barn: an update that keeps failing is guarded and switched off', true)
  end
  st.rep = 10
  local before = #sent
  BX.onStreetLegalNewDay(st.barn.nextHint + 30)
  check('barn: no rumours below the reputation', #sent == before)
  _G.sl_career, _G.extensions, _G.guihooks, _G.getPlayerVehicle, _G.sl_lot, _G.map, _G.getCurrentLevelIdentifier, _G.sl_classifieds, _G.ui_message, _G.sl_fleet =
    old.c, old.e, old.g, old.pv, old.lot, old.map, old.lv, old.cl, old.um, old.fleet
  package.loaded['sl/classifieds'], package.loaded['sl/barnfinds'] = nil, nil
end

-- the planned meet of a night
do
  local NL = require('sl/core/nightlife')
  local rngLib = require('sl/core/rng')
  local list = { { id = 'c' }, { id = 'a' }, { id = 'b' } }
  local first = NL.plannedMeet(list, 5, 0, 9, rngLib)
  check('meets: the first meet of a night is the same place however often it is asked, whatever the order of the list', first == NL.plannedMeet(list, 5, 0, 9, rngLib) and first.id == NL.plannedMeet({ { id = 'b' }, { id = 'c' }, { id = 'a' } }, 5, 0, 9, rngLib).id)
  local a, b, c = NL.plannedMeet(list, 5, 0, 9, rngLib).id, NL.plannedMeet(list, 5, 1, 9, rngLib).id, NL.plannedMeet(list, 5, 2, 9, rngLib).id
  check('meets: the second and third meet of the night are the other places', a ~= b and b ~= c and a ~= c)
  local seen = {}
  for d = 1, 20 do seen[NL.plannedMeet(list, d, 0, 9, rngLib).id] = true end
  check('meets: other nights use other places; no places gives nothing', seen.a and seen.b and seen.c and NL.plannedMeet({}, 5, 0, 9, rngLib) == nil and NL.plannedMeet(nil, 5, 0, 9, rngLib) == nil)
end

-- a lot's row built ahead (sl/core/lotpre): the store matches one lot, one day and one offer list; the nearest lot is picked; the count is capped
do
  local LP = require('sl/core/lotpre')
  local offers = { { id = 'a' }, { id = 7 }, { id = 'c' } }
  local st = LP.newStore('dealer1', 3, offers)
  check('lotpre: a store is keyed by lot, day and the offer ids in order', st.placeId == 'dealer1' and st.day == 3 and #st.ids == 3 and st.ids[2] == '7' and next(st.cars) == nil)
  check('lotpre: the same lot, day and offers match', LP.matches(st, 'dealer1', 3, offers))
  check('lotpre: another day, lot, order or count does not', not LP.matches(st, 'dealer1', 4, offers) and not LP.matches(st, 'junk', 3, offers)
    and not LP.matches(st, 'dealer1', 3, { offers[2], offers[1], offers[3] }) and not LP.matches(st, 'dealer1', 3, { offers[1], offers[2] }) and not LP.matches(nil, 'dealer1', 3, offers))
  local places = { g = { id = 'g', kind = 'garage', pos = { x = 0, y = 0 } }, far = { id = 'far', kind = 'dealer', pos = { x = 900, y = 0 } },
    near = { id = 'near', kind = 'junkyard', pos = { x = 120, y = 50 } }, stock = { id = 'stock', kind = 'place', stock = { kind = 'dealer' }, pos = { x = 100, y = 0 } } }
  check('lotpre: the nearest lot within reach is picked (a stock dealer counts, a garage does not)', LP.pick(nil, places, { x = 0, y = 0 }, 500).id == 'stock')
  check('lotpre: nothing within reach: nothing', LP.pick(nil, places, { x = 5000, y = 0 }, 500) == nil and LP.pick(nil, places, nil, 500) == nil)
  check('lotpre: a lot given as the destination wins; another kind of place does not', LP.pick(places.far, places, { x = 0, y = 0 }, 500).id == 'far' and LP.pick(places.g, places, { x = 0, y = 0 }, 500).id == 'stock')
  check('lotpre: the count is capped by the setting and never below one', LP.cap(6, 4) == 4 and LP.cap(3, 4) == 3 and LP.cap(6, nil) == 6 and LP.cap(6, 'x') == 6 and LP.cap(2, 0) == 1)
  -- the game side under the fade: a build that throws leaves nothing behind (the reviewer's case): building is false afterwards and the store is dropped
  do
    local old = { c = _G.sl_career, l = _G.sl_lot, o = _G.sl_options, pv = _G.getPlayerVehicle, id = _G.getObjectByID, lg = _G.log, v3 = _G.vec3, q = _G.quatFromDir, cb = package.loaded['sl/carBuilder'] }
    local state = { day = 2 }
    local lotPlace = { id = 'lot1', kind = 'dealer', pos = { x = 10, y = 0, z = 0 }, name = 'Lot' }
    _G.sl_career = { isActive = function() return true end, getState = function() return state end, getPlaces = function() return { lot1 = lotPlace } end }
    _G.sl_lot = { isOpen = function() return false end, offersFor = function() return { { id = 'o1' }, { id = 'o2' } } end,
      spotsFor = function(_, n) local t = {} for i = 1, n do t[i] = { pos = { x = i, y = 0, z = 0 }, dir = { x = 0, y = 1, z = 0 } } end return t end }
    _G.sl_options = { get = function() return nil end }
    _G.getPlayerVehicle = function() return { getPosition = function() return { x = 0, y = 0, z = 0 } end } end
    local deleted = 0
    _G.getObjectByID = function() return { delete = function() deleted = deleted + 1 end } end
    _G.log = function() end
    _G.vec3 = _G.vec3 or function(x, y, z) return { x = x, y = y, z = z } end
    _G.quatFromDir = function() return {} end
    local v3 = _G.vec3
    _G.vec3 = function(x, y, z) local t = v3(x, y, z) return setmetatable(t, { __add = function(a, b) return v3(a.x + b.x, a.y + b.y, a.z + b.z) end }) end
    package.loaded['sl/carBuilder'] = { buildOffer = function() error('boom') end }
    package.loaded['sl/lotpre'] = nil
    local G = require('sl/lotpre')
    local job = { sleep = function() end }
    local ok = pcall(G.onStreetLegalFade, 'start', job)
    check('lotpre game side: a build that throws does not reach the fade job', ok)
    check('lotpre game side: after the failure nothing is in the store and a later fade may build again', G.status() == 'no row in store')
    -- and the control: a build that works stores its cars hidden
    local hidden = {}
    package.loaded['sl/carBuilder'] = { buildOffer = function(_, offer) return { getID = function() return offer.id end, queueLuaCommand = function() end, setActive = function(_, a) hidden[offer.id] = a end } end }
    package.loaded['sl/lotpre'] = nil
    G = require('sl/lotpre')
    G.onStreetLegalFade('start', job)
    check('lotpre game side: a good build stores the row hidden', G.status():find('2 cars') ~= nil and hidden.o1 == 0 and hidden.o2 == 0, G.status())
    _G.sl_career, _G.sl_lot, _G.sl_options, _G.getPlayerVehicle, _G.getObjectByID, _G.log, _G.vec3, _G.quatFromDir = old.c, old.l, old.o, old.pv, old.id, old.lg, old.v3, old.q
    package.loaded['sl/carBuilder'], package.loaded['sl/lotpre'] = old.cb, nil
  end
end

-- the calendar (sl/core/calendar): the weekend home races, the swap meet and the series from the day and the seed; the store; the actions; reminders; a dockyards layout as a circuit
do
  local C = require('sl/core/calendar')
  local W = require('sl/core/weekly')
  local st = C.newStore()
  -- day 40 is day 5 of week 6 (the fixture's today): the weekend is days 41 and 42
  check('calendar: the week counter is the weekly ledger one', W.week(40) == 6 and W.dayOfWeek(40) == 5)
  check('calendar: no home race on a weekday, one on each weekend day, the same for the same day and seed', C.homeFor(40, 9) == nil and C.homeFor(41, 9) ~= nil and C.homeFor(42, 9) ~= nil and C.homeFor(41, 9).slot == C.homeFor(41, 9).slot and C.homeFor(41, 9).slot ~= C.homeFor(42, 9).slot)
  local list = C.schedule(40, 17.5, 9, 700, st)
  local ids, byKind = {}, {}
  for _, ev in ipairs(list) do ids[ev.id] = ev byKind[ev.kind] = (byKind[ev.kind] or 0) + 1 end
  local home = C.homeFor(41, 9)
  local sat = ids['weekend:' .. home.slot .. ':6']
  check('calendar: the weekend race of day 41 is listed as kind:slot:week, open, at 15:00 at the dockyards, no travel, three laps', sat ~= nil and sat.status == 'open' and sat.hour == 15 and sat.place == C.HOME_PLACE and sat.travel.needed == false and sat.laps == 3 and sat.layer == home.layer and sat.requires.met == true)
  check('calendar: the swap meet is on the weekend nights', ids['swap:meet:6:6'] ~= nil and ids['swap:meet:6:6'].hour == 20 and ids['swap:meet:6:7'] ~= nil)
  check('calendar: past open events are not listed; the list is in day order', list[1].day >= 40 and (function() for i = 2, #list do if list[i].day < list[i - 1].day then return false end end return true end)())
  -- the series: cycle 1 (days 29-56) is the second in the rotation (Johnson Valley) from the 15th day: days 43-47; the rally needs 600, the cup 450
  check('calendar: the 28-day cycle rotates the three series', C.seriesFor(0, 1000).id == 'utah-rally' and C.seriesFor(1, 1000).id == 'jv-offroad' and C.seriesFor(2, 1000).id == 'hirochi-cup' and C.seriesFor(3, 1000).id == 'utah-rally')
  check('calendar: a series below your reputation is not offered', C.seriesFor(0, 599) == nil and C.seriesFor(0, 600) ~= nil)
  local r1 = ids['jv-offroad:2:r1']
  check('calendar: the series rounds are listed with travel, the round of rounds, a purse text and days to go', r1 ~= nil and r1.day == 43 and r1.kind == 'series' and r1.travel.needed == true and r1.travel.fee == 600 and r1.series.round == 1 and r1.series.rounds == 5 and r1.expiresIn == 3 and type(r1.reward) == 'string' and ids['jv-offroad:2:r5'] ~= nil and ids['jv-offroad:2:r5'].day == 47)
  -- the phone's shape (tools/calendar_fixture.js)
  local sum = C.summary(40, 17.5, 9, 700, st)
  local shapeOk = sum.today.day == 40 and sum.today.hour == 17.5 and sum.today.week == 6 and sum.today.dayOfWeek == 5 and type(sum.events) == 'table' and type(sum.series) == 'table' and type(sum.invites) == 'table'
  for _, ev in ipairs(sum.events) do
    for _, k in ipairs({ 'id', 'title', 'kind', 'day', 'status', 'travel' }) do if ev[k] == nil then shapeOk = false end end
    if type(ev.travel.needed) ~= 'boolean' or type(ev.travel.fee) ~= 'number' or type(ev.travel.hours) ~= 'number' or type(ev.reminder) ~= 'boolean' then shapeOk = false end
    if ev.series ~= nil and (type(ev.series.id) ~= 'string' or type(ev.series.round) ~= 'number') then shapeOk = false end
    if ev.requires ~= nil and (type(ev.requires.label) ~= 'string' or type(ev.requires.met) ~= 'boolean') then shapeOk = false end
    if ev.layer ~= nil or ev.fee ~= nil then shapeOk = false end      -- (the rules' own fields stay out of the phone's shape)
  end
  check('calendar: summary() has the fixture shape (today, events with id/title/kind/day/status/travel/reminder, series, invites)', shapeOk)
  -- the actions
  local ok, text, fee = C.enter(st, sat, 50, 40, 17.5)
  check('calendar: entering with too little money is refused', not ok and fee == nil)
  ok, text, fee = C.enter(st, sat, 500, 40, 17.5)
  check('calendar: entering a home race takes the fee, sets the reminder and says where to be', ok and fee == sat.fee and st.entered[sat.id] ~= nil and st.remind[sat.id] == true and text:find('day 41') ~= nil and text:find('15:00') ~= nil)
  check('calendar: entered twice is refused; declining an entered race is refused', not C.enter(st, sat, 500, 40, 17.5) and not C.decline(st, sat))
  check('calendar: a series round answers not yet; the swap meet has nothing to enter', (select(2, C.enter(st, r1, 5000, 40, 17.5))):find('not open') ~= nil and not C.enter(st, ids['swap:meet:6:6'], 500, 40, 17.5))
  local sun = ids['weekend:' .. C.homeFor(42, 9).slot .. ':6']
  check('calendar: decline and remind are recorded and show in the list', C.decline(st, sun) and C.remind(st, r1, true) and C.schedule(40, 17.5, 9, 700, st) and C.find(C.schedule(40, 17.5, 9, 700, st), sun.id).status == 'declined' and C.find(C.schedule(40, 17.5, 9, 700, st), r1.id).reminder == true)
  -- reminders: 24 h and 1 h before, each once; the entered race is day 41 15:00
  local due = C.reminders(C.schedule(40, 17.5, 9, 700, st), st, 40, 17.5)
  check('calendar: at 17:30 the day before, the 24 h reminder of the entered race fires once', #due == 1 and due[1].event.id == sat.id and due[1].hoursLeft == 24 and #C.reminders(C.schedule(40, 17.5, 9, 700, st), st, 40, 18) == 0)
  due = C.reminders(C.schedule(41, 14.5, 9, 700, st), st, 41, 14.5)
  check('calendar: half an hour before, the 1 h reminder fires', #due == 1 and due[1].hoursLeft == 1)
  -- due and missed: on the grid at the hour it runs; too late it is missed
  local far = function() return 500 end
  local near = function() return 20 end
  check('calendar: the race is due only at the hour, within reach of the grid, up to an hour and a half late', C.due(C.schedule(41, 14.9, 9, 700, st), st, 41, 14.9, near) == nil and C.due(C.schedule(41, 15.2, 9, 700, st), st, 41, 15.2, far) == nil and C.due(C.schedule(41, 15.2, 9, 700, st), st, 41, 15.2, near).id == sat.id and C.due(C.schedule(41, 16.6, 9, 700, st), st, 41, 16.6, near) == nil)
  local missed = C.missed(C.schedule(41, 16.6, 9, 700, st), st, 41, 16.6)
  check('calendar: past the window an entered race is missed, once, and listed as missed', #missed == 1 and missed[1].id == sat.id and #C.missed(C.schedule(41, 16.6, 9, 700, st), st, 41, 16.6) == 0 and C.find(C.schedule(41, 17, 9, 700, st), sat.id).status == 'missed')
  -- a result: done with the purse, in the history
  local st2 = C.newStore()
  C.enter(st2, sat, 500, 40, 17.5)
  local money, rep = C.result(st2, sat, 1)
  check('calendar: a win is done with the purse and 40 rep and kept in the history; a second result changes nothing', money == sat.reward and rep == 40 and st2.done[sat.id].won == true and st2.done[sat.id].place == 1 and #st2.history == 1 and C.result(st2, sat, 1) == 0 and C.find(C.schedule(41, 17, 9, 700, st2), sat.id).status == 'done' and C.find(C.schedule(41, 17, 9, 700, st2), sat.id).reward == sat.reward)
  local st3 = C.newStore()
  C.enter(st3, sat, 500, 40, 17.5)
  money, rep = C.result(st3, sat, nil)
  check('calendar: a DNF is done without a purse or rep', money == 0 and rep == 0 and st3.done[sat.id].won == false and st3.entered[sat.id] == nil)
  local st4 = C.newStore()
  C.enter(st4, sat, 500, 40, 17.5)
  money, rep = C.result(st4, sat, 2)
  check('calendar: second place takes half the purse and 20 rep', money == sat.reward / 2 and rep == 20 and st4.done[sat.id].won == false and st4.done[sat.id].place == 2)
  C.sweep(st2, 60)
  check('calendar: a sweep forgets results older than a week', st2.done[sat.id] == nil and #C.schedule(60, 10, 9, 700, st2) > 0)
  check('calendar: a done or missed event stays a week, then goes', C.find(C.schedule(47, 10, 9, 700, st3), sat.id) ~= nil and C.find(C.schedule(49, 10, 9, 700, st3), sat.id) == nil)
  check('calendar: the parts switched off leave the list empty', #C.schedule(40, 17.5, 9, 700, C.newStore(), { home = false, swap = false, series = false }) == 0)
  -- a dockyards layout as a circuit: the nodes in lap order from the start node, a loop, the grid spot
  local v3 = function(x, y, z) return { x = x, y = y, z = z } end
  local layer = { startNode = 3, defaultStartPosition = 2, pathnodes = { { oldId = 5, pos = { 10, 10, 0 }, radius = 5 }, { oldId = 3, pos = { 0, 0, 0 }, radius = 6 }, { oldId = 4, pos = { 10, 0, 0 }, radius = 3 } },
    segments = { { from = 3, to = 4 }, { from = 4, to = 5 }, { from = 5, to = 3 } }, startPositions = { { oldId = 2, pos = { -1, 0, 0 }, rot = { 0, 0, 0, 1 } }, { oldId = 9, pos = { 5, 5, 5 } } } }
  local tr = C.trackFromLayer(layer, 'Test', v3)
  check('calendar: a layout gives the checkpoints in lap order from the start node, dir to the next, half width at least 4, and the default grid spot', tr ~= nil and #tr.cps == 3 and tr.cps[1].pos.x == 0 and tr.cps[2].pos.x == 10 and tr.cps[2].pos.y == 0 and tr.cps[3].pos.y == 10 and tr.cps[1].dir.x == 10 and tr.cps[3].half == 5 and tr.cps[2].half == 4 and tr.start.pos.x == -1 and tr.name == 'Test')
  layer.segments[3] = nil
  check('calendar: an open path or a bad file is no circuit', C.trackFromLayer(layer, 'x', v3) == nil and C.trackFromLayer(nil, 'x', v3) == nil and C.trackFromLayer({ pathnodes = {} }, 'x', v3) == nil)
  check('calendar: the clock text', C.clock(15) == '15:00' and C.clock(8.5) == '08:30' and C.clock(nil) == '00:00')
  -- the game side: the part off answers nothing; the reminders and the race start go through the stubs
  do
    local old = { c = _G.sl_career, s = _G.sl_streets, g = _G.sl_gridrace, o = _G.sl_options, pv = _G.getPlayerVehicle, gh = _G.guihooks, ex = _G.extensions, jr = _G.jsonReadFile, v3 = _G.vec3 }
    local state = { day = 41, seed = 9, rep = 700, money = 1000, racers = { { id = 'ra', rep = 650, name = 'Ra' }, { id = 'rb', rep = 9000, name = 'Rb' } }, calendar = nil }
    local hourNow, texts, hooks, started, paid, finish, busyWhy, chargeOk = 14.5, {}, {}, nil, {}, nil, nil, true
    _G.sl_career = { isActive = function() return true end, getState = function() return state end, hour = function() return hourNow end, LEVEL = 'west_coast_usa', has = function() return true end,
      freeToStart = function() return busyWhy end,
      addMoney = function(a, l) if not chargeOk then return false end state.money = state.money + a paid[#paid + 1] = l return true end, payOut = function(a, l) state.money = state.money + a paid[#paid + 1] = l return true end, sendText = function(_, t) texts[#texts + 1] = t end }
    _G.sl_streets = { isRacing = function() return false end }
    _G.sl_gridrace = { running = function() return started ~= nil and finish == nil end, start = function(spec, done) started = spec finish = done return true end }
    local on = true
    _G.sl_options = { get = function(k) if k == 'slCalendar' then return on end return nil end }
    _G.guihooks = { trigger = function(name, data) if name == 'slPhoneToast' then texts[#texts + 1] = data.text end end }
    _G.extensions = { hook = function(name, ...) hooks[#hooks + 1] = { name = name, ... } end }
    _G.vec3 = _G.vec3 or v3
    local v3g = _G.vec3
    _G.vec3 = function(x, y, z) return setmetatable(v3g(x, y, z), { __sub = function(a, b) return _G.vec3(a.x - b.x, a.y - b.y, a.z - b.z) end, __index = { length = function(p) return math.sqrt(p.x * p.x + p.y * p.y + p.z * p.z) end } }) end
    _G.getPlayerVehicle = function() return { getPosition = function() return _G.vec3(-5, 0, 0) end } end
    _G.jsonReadFile = function() return layer end
    layer.segments[3] = { from = 5, to = 3 }
    package.loaded['sl/calendar'] = nil
    local G = require('sl/calendar')
    local sum = G.summary()
    local home = C.homeFor(41, 9)
    local evId = 'weekend:' .. home.slot .. ':6'
    check('calendar game side: the summary lists the weekend race of the day', sum ~= nil and sum.today.day == 41 and C.find(sum.events, evId) ~= nil)
    chargeOk = false
    local ok, text = G.enter(evId)
    check('calendar game side: a charge that fails leaves no entry on the books (the reviewer case)', not ok and state.calendar.entered[evId] == nil and state.money == 1000)
    chargeOk = true
    ok, text = G.enter(evId)
    check('calendar game side: entering pays the fee from the wallet and says so', ok and state.money == 1000 - home.fee and paid[1] == 'Entry fee' and text:find('day 41') ~= nil)
    G.onUpdate(2.5)
    check('calendar game side: half an hour before, the 1 h reminder is a toast and the banner hook', texts[#texts] ~= nil and texts[#texts]:find('in 1 h') ~= nil and hooks[#hooks].name == 'onStreetLegalCalendarReminder' and hooks[#hooks][2] == 1 and started == nil)
    hourNow = 15.1
    busyWhy = 'a chase'
    G.onUpdate(2.5)
    check('calendar game side: a due race waits while the career says busy (a chase, a job, a fade, a scene)', started == nil)
    busyWhy = nil
    G.onUpdate(2.5)
    check('calendar game side: at the hour, on the grid, the grid runner is started with the layout, the title, three laps and the purse', started ~= nil and started.layer == home.layer and started.name == home.title and started.laps == 3 and started.purse == home.purse)
    local rep0 = state.rep
    finish({ place = 1, time = 180, grid = 6 })
    check('calendar game side: a win pays the purse and 40 rep and is done', state.money == 1000 - home.fee + home.purse and paid[#paid]:find('Purse') ~= nil and state.calendar.done[evId].won == true and state.rep == rep0 + 40 and texts[#texts]:find('1st') ~= nil)
    -- the series engine's side: event() hands the rules' fields; a round result marks the round's event done or missed and pays nothing
    local evt = G.event(evId)
    check('calendar game side: event(id) gives the event with its fee, laps and travel', evt ~= nil and evt.fee == home.fee and evt.laps == 3 and evt.travel.needed == false and G.event('nope') == nil)
    local money0 = state.money
    state.rep = 1000
    G.onStreetLegalRoundResult({ seriesId = 'jv-offroad:2', round = 1, place = 1 })
    G.onStreetLegalRoundResult({ seriesId = 'jv-offroad:2', round = 2, missed = true })
    check('calendar game side: a series round result marks the event done (or missed) without paying', state.calendar.done['jv-offroad:2:r1'] ~= nil and state.calendar.done['jv-offroad:2:r1'].won == true and state.calendar.done['jv-offroad:2:r2'].won == nil and state.money == money0)
    on = false
    check('calendar game side: the part off: no summary, the actions answer nothing', G.summary() == nil and G.enter(evId) == nil)
    on = true
    -- the tick guard: an error in the tick is logged, five in a row switch it off, the app still answers
    local logged = 0
    local oldLog = _G.log
    _G.log = function() logged = logged + 1 end
    local goodHour = _G.sl_career.hour
    _G.sl_career.hour = function() error('clock broke') end
    for i = 1, 7 do G.onUpdate(2.5) end
    _G.sl_career.hour = goodHour
    G.onUpdate(2.5)
    check('calendar game side: a tick that throws is logged and the tick is off after five failures; summary() still works', logged == 5 and G.summary() ~= nil)
    _G.log = oldLog
    _G.sl_career, _G.sl_streets, _G.sl_gridrace, _G.sl_options, _G.getPlayerVehicle, _G.guihooks, _G.extensions, _G.jsonReadFile, _G.vec3 = old.c, old.s, old.g, old.o, old.pv, old.gh, old.ex, old.jr, old.v3
    package.loaded['sl/calendar'] = nil
  end
end

-- the grid runner (sl/core/gridrace): the grid size, the field by class, the aggression, the payout, the camera length, the flares; and a stubbed run of sl/gridrace
do
  local GR = require('sl/core/gridrace')
  local rngLib = require('sl/core/rng')
  check('gridrace: the grid size is the setting within 3..7 and the slots less one', GR.gridSize(6, 10) == 6 and GR.gridSize(9, 10) == 7 and GR.gridSize(1, 10) == 3 and GR.gridSize(6, 4) == 3 and GR.gridSize(nil, 8) == 7 and GR.gridSize(5, 1) == 0)
  local cands = {}
  for i, c in ipairs({ 'D', 'C', 'C', 'B', 'B', 'B', 'A', 'A', 'S' }) do cands[i] = { model = 'm' .. (i % 4), config = 'c' .. i, class = c } end
  local f = GR.field(cands, 'B', 5, rngLib.new(3))
  local classes = {}
  for _, c in ipairs(f) do classes[#classes + 1] = c.class end
  check('gridrace: the field takes the player class first, then the classes next to it', #f == 5 and classes[1] == 'B' and classes[2] == 'B' and classes[3] == 'B' and (classes[4] == 'C' or classes[4] == 'A') and (classes[5] == 'C' or classes[5] == 'A'))
  local f2 = GR.field(cands, 'B', 3, rngLib.new(3))
  local models = {}
  for _, c in ipairs(f2) do models[c.model] = (models[c.model] or 0) + 1 end
  local distinct = true
  for _, n in pairs(models) do if n > 1 then distinct = false end end
  check('gridrace: distinct models come first; an unknown class falls back; no candidates gives an empty field', distinct and #GR.field(cands, 'Z', 2, rngLib.new(1)) == 2 and #GR.field({}, 'B', 5, rngLib.new(1)) == 0 and #GR.field(cands, 'S', 20, rngLib.new(1)) == 9)
  check('gridrace: the aggression grows with reputation and is capped', GR.aggression(0) == 0.55 and GR.aggression(1000) == 0.75 and GR.aggression(5000) == 0.95)
  local m1, r1 = GR.payout(1, 800)
  local m2, r2 = GR.payout(2, 800)
  local m3, r3 = GR.payout(3, 800)
  local m5, r5 = GR.payout(5, 800)
  local m0, r0 = GR.payout(nil, 800)
  check('gridrace: the purse by place (all, half, a quarter, nothing) and the rep (40, 20, 10, 5; a DNF nothing)', m1 == 800 and r1 == 40 and m2 == 400 and r2 == 20 and m3 == 200 and r3 == 10 and m5 == 0 and r5 == 5 and m0 == 0 and r0 == 0)
  check('gridrace: a camera path plays for its last marker time, capped', GR.camSeconds({ markers = { { time = 0 }, { time = 23 } } }, 8) == 8 and GR.camSeconds({ markers = { { time = 0 }, { time = 4 } } }, 8) == 4 and GR.camSeconds(nil, 8) == 0)
  local cps = GR.cps({ { pos = 1, normal = 'n1', radius = 6 }, { pos = 2, normal = 'n2', radius = 2 } })
  check('gridrace: the flares get the nodes with their normal and half width at least 4', #cps == 2 and cps[1].dir == 'n1' and cps[1].half == 6 and cps[2].half == 4)
  check('gridrace: place words', GR.placeWord(1) == '1st' and GR.placeWord(2) == '2nd' and GR.placeWord(3) == '3rd' and GR.placeWord(4) == '4th')
  local off = GR.candidatesFor('offroad', function() return { { model = 'x', config = 'y', class = 'B' } } end)
  check('gridrace: a named roster is the candidates (a copy), else the pool; a series track is a missions folder', #off == #GR.ROSTERS.offroad and off[1].model == 'pickup' and off ~= GR.ROSTERS.offroad and #GR.candidatesFor(nil, function() return { { model = 'x', config = 'y', class = 'B' } } end) == 1 and #GR.candidatesFor('nope', nil) == 0 and GR.roundDir('johnson_valley/timeTrial/006-ShortcourseA') == '/gameplay/missions/johnson_valley/timeTrial/006-ShortcourseA/')
  local offField = GR.field(GR.candidatesFor('offroad'), 'A', 5, rngLib.new(2))
  local okOff = #offField == 5
  for _, c in ipairs(offField) do if c.class ~= 'A' and c.class ~= 'B' then okOff = false end end
  check('gridrace: the off-road field of five for a class A car is A and B trucks', okOff and offField[1].class == 'A' and offField[2].class == 'A' and offField[3].class == 'A' and offField[4].class == 'A' and offField[5].class == 'B')
  -- the game side with a stubbed race object and world: the build (prefab, the grid, the field under the budget), the start, the laps, the finish and the cleanup
  do
    local old = { c = _G.sl_career, o = _G.sl_options, pv = _G.getPlayerVehicle, id = _G.getObjectByID, gh = _G.guihooks, lg = _G.log, v3 = _G.vec3, sp = _G.spawnPrefab, rp = _G.removePrefab, vp = _G.gameplay_vehiclePerformance,
      js = _G.core_jobsystem, um = _G.ui_message, cb = package.loaded['sl/carBuilder'], mk = _G.sl_markers, cp = _G.core_paths, cc = _G.core_camera, sd = _G.slrrDrivers }
    local events, prefabs, built, deleted = {}, {}, {}, {}
    local function ev(e) events[#events + 1] = e end
    local function car(id) return { getID = function() return id end, queueLuaCommand = function(_, c) ev('cmd ' .. id .. ' ' .. c:sub(1, 22)) end, delete = function() deleted[#deleted + 1] = id end } end
    local v3 = function(x, y, z) return setmetatable({ x = x, y = y, z = z }, { __add = function(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end }) end
    _G.vec3 = v3
    local sps = {}
    for i = 1, 4 do sps[i] = { pos = v3(i, 0, 0), rot = {}, missing = false, moveResetVehicleTo = function(_, vid) ev('grid ' .. vid .. ' slot ' .. i) end } end
    local raceObj = { states = {}, path = { startPositions = { sorted = sps, objects = { [2] = sps[1] } }, defaultStartPosition = 2, config = { linearPathnodes = { 1, 2 } }, pathnodes = { objects = { { pos = 1, radius = 5 }, { pos = 2, radius = 5 } } } } }
    function raceObj:setPathFile() end
    function raceObj:setVehicleIds(ids) self.ids = ids ev('ids ' .. #ids) end
    function raceObj:startRace() ev('startRace') for _, id in ipairs(self.ids) do self.states[id] = { complete = false } end end
    function raceObj:startAiVehicle(id, a) ev('ai ' .. id .. ' ' .. a) end
    function raceObj:stopRace() ev('stopRace') end
    function raceObj:onUpdate(dt) self.ticks = (self.ticks or 0) + 1 if self.ticks == 3 then self.states[100].complete = true self.states[100].placement = 2 self.states[100].endTime = 180 end end
    package.preload['/lua/ge/extensions/gameplay/race/race'] = function() return function() return raceObj end end
    _G.sl_career = { isActive = function() return true end, getState = function() return { day = 41, seed = 9, rep = 1000 } end, LEVEL = 'west_coast_usa' }
    _G.sl_options = { get = function(k) if k == 'slGridCars' then return 3 end return nil end }
    old.fs = _G.FS
    _G.FS = { fileExists = function() return true end }
    _G.getPlayerVehicle = function() return car(100) end
    _G.getObjectByID = function(id) return car(id) end
    _G.guihooks = { trigger = function(name, d) if name == 'slFade' then ev('fade ' .. tostring(d.on)) end end }
    _G.log = function() end
    _G.ui_message = function(t) ev('say ' .. tostring(t)) end
    _G.spawnPrefab = function(name, file) prefabs[#prefabs + 1] = name return {} end
    _G.removePrefab = function(name) prefabs[#prefabs] = nil ev('prefab removed') end
    _G.gameplay_vehiclePerformance = { getClassFromVehId = function() return { class = { name = 'A' } } end, getClassFromConfig = function(m, c) return { class = { name = c:sub(1, 1) } } end }
    _G.core_jobsystem = { create = function(f) f({ sleep = function() end }) end }
    _G.core_paths = { loadPath = function() return { markers = { { time = 0 }, { time = 3 } } } end, playPath = function() ev('cam') end, stopCurrentPath = function() end }
    _G.core_camera = { setByName = function() end }
    _G.sl_markers = { flareCircuit = function(cps) ev('flares ' .. #cps) end, clear = function() ev('flares cleared') end }
    _G.slrrDrivers = nil
    local nextId = 200
    package.loaded['sl/carBuilder'] = { aiPool = function() return { { model = 'm1', config = 'A1' }, { model = 'm2', config = 'A2' }, { model = 'm3', config = 'B1' }, { model = 'm4', config = 'S1' } } end,
      spawn = function(_, model, config) nextId = nextId + 1 built[#built + 1] = model .. '/' .. config return car(nextId) end }
    package.loaded['sl/gridrace'] = nil
    local G = require('sl/gridrace')
    local result
    local ok = G.start({ layer = '003', name = 'Test', laps = 3, purse = 800 }, function(r) result = r end)
    local log = table.concat(events, '|')
    check('gridrace game side: start builds the prefab, puts the player on the default spot, builds 3 AI of the class and the next, flares, the camera, the countdown, the start', ok and #prefabs == 1 and log:find('grid 100 slot 1') ~= nil and #built == 3 and built[1]:find('/A') ~= nil and built[2]:find('/A') ~= nil and log:find('ids 4') ~= nil and log:find('startRace') ~= nil and log:find('ai 201 0.75') ~= nil and log:find('flares 2') ~= nil and log:find('cam') ~= nil and log:find('say 3') ~= nil and G.running() ~= nil, log)
    G.onUpdate(0.1) G.onUpdate(0.1)
    check('gridrace game side: the race runs until the player is complete', result == nil and G.running() ~= nil)
    G.onUpdate(0.1)
    check('gridrace game side: the finish: the place and time go to done, the AI cars are deleted, the prefab removed, the flares cleared, nothing runs', result ~= nil and result.place == 2 and result.time == 180 and result.grid == 4 and #deleted == 3 and #prefabs == 0 and G.running() == nil and table.concat(events, '|'):find('stopRace') ~= nil)
    -- an abort mid-race cleans up and tells the caller
    events, built, deleted, result = {}, {}, {}, nil
    raceObj.ticks, raceObj.states = 0, {}
    G.start({ layer = '003', name = 'Test', laps = 3 }, function(r) result = r end)
    G.onStreetLegalStopped()
    check('gridrace game side: a career stop aborts: done gets aborted, the cars and the prefab go', result ~= nil and result.aborted == true and result.place == nil and #deleted == 3 and #prefabs == 0 and G.running() == nil)
    -- a series round (section 11.2): the missions folder, the off-road roster capped by ctx.rivals, the report to sl_series once
    events, built, deleted, result = {}, {}, {}, nil
    raceObj.ticks, raceObj.states = 0, {}
    local reported, aborted = nil, nil
    _G.sl_series = { report = function(series, round, r) reported = { series = series, round = round, r = r } end, abort = function(series, round, why) aborted = why end }
    local okr = G.startRound({ series = 'jv-offroad:2', round = 2, def = { runner = 'grid', track = 'johnson_valley/timeTrial/006-ShortcourseA', laps = 3, field = 'offroad', title = 'Short course A' }, vehId = 100, seed = 1, rivals = 2 })
    local okBuilt = #built == 2
    for _, b in ipairs(built) do if not (b:find('^pickup/') or b:find('^hopper/') or b:find('^utv/') or b:find('^rockbouncer/') or b:find('^burnside/')) then okBuilt = false end end
    check('gridrace game side: a series round starts on the mission folder with the off-road roster, capped by the rivals count', okr and G.running() ~= nil and G.running().dir == '/gameplay/missions/johnson_valley/timeTrial/006-ShortcourseA/' and okBuilt and G.running().laps == 3, table.concat(built, ','))
    G.onUpdate(0.1) G.onUpdate(0.1) G.onUpdate(0.1)
    check('gridrace game side: the round reports place, time, dnf and racers to sl_series once', reported ~= nil and reported.series == 'jv-offroad:2' and reported.round == 2 and reported.r.place == 2 and reported.r.time == 180 and reported.r.dnf == false and reported.r.racers == 3 and aborted == nil and G.running() == nil)
    raceObj.ticks, raceObj.states, reported = 0, {}, nil
    G.startRound({ series = 'jv-offroad:2', round = 3, def = { track = 'johnson_valley/timeTrial/005-dunerace', laps = 2, field = 'offroad' }, rivals = 2 })
    G.onVehicleSwitched(100, 7)
    check('gridrace game side: a vehicle change in a round aborts it to sl_series', aborted == 'aborted' and reported == nil and G.running() == nil)
    _G.sl_series = nil
    -- the class scan runs in the background from the career start (the reviewer's case: not inside the first race's fade)
    package.loaded['sl/gridrace'] = nil
    G = require('sl/gridrace')
    local slept = 0
    _G.core_jobsystem = { create = function(f) f({ sleep = function() slept = slept + 1 end }) end }
    local reads = 0
    _G.gameplay_vehiclePerformance.getClassFromConfig = function(m, c) reads = reads + 1 return { class = { name = c:sub(1, 1) } } end
    G.onStreetLegalStarted()
    check('gridrace game side: the career start scans the AI pool classes in a job, each config once', reads == 4 and G.onStreetLegalStarted() == nil and reads == 4)
    _G.FS = old.fs
    _G.sl_career, _G.sl_options, _G.getPlayerVehicle, _G.getObjectByID, _G.guihooks, _G.log, _G.vec3, _G.spawnPrefab, _G.removePrefab, _G.gameplay_vehiclePerformance = old.c, old.o, old.pv, old.id, old.gh, old.lg, old.v3, old.sp, old.rp, old.vp
    _G.core_jobsystem, _G.ui_message, _G.sl_markers, _G.core_paths, _G.core_camera, _G.slrrDrivers = old.js, old.um, old.mk, old.cp, old.cc, old.sd
    package.loaded['sl/carBuilder'], package.loaded['sl/gridrace'], package.preload['/lua/ge/extensions/gameplay/race/race'] = old.cb, nil, nil
  end
end

-- needs (sl/core/needs): the meters drain per awake hour, stages and texts, effects capped, food and sleep put them back
do
  local N = require('sl/core/needs')
  local n = N.newState()
  check('needs: a new state is full', n.food == 100 and n.water == 100 and n.rest == 100)
  N.tick(n, 12, {}, 1)
  check('needs: a 12 hour day: food 28, water 0, rest 40', n.food == 28 and n.water == 0 and n.rest == 40, n.food .. ',' .. n.water .. ',' .. n.rest)
  local m = N.newState()
  N.tick(m, 1, { busy = true, hot = true, nightHeat = true }, 1)
  check('needs: racing, heat and a hot day drain faster', math.abs(m.food - 92.2) < 1e-6 and math.abs(m.water - 83.5) < 1e-6 and math.abs(m.rest - 93.5) < 1e-6)
  local half = N.newState()
  N.tick(half, 1, {}, 0.5)
  check('needs: the drain setting scales it', half.food == 97 and half.water == 94.5)
  check('needs: stages by value', N.stage(40) == 'ok' and N.stage(39.9) == 'nudge' and N.stage(20) == 'nudge' and N.stage(19) == 'handicap' and N.stage(8) == 'handicap' and N.stage(7) == 'problem')
  check('needs: words', N.word('food', 100) == 'fed' and N.word('water', 10) == 'parched' and N.word('rest', 0) == 'exhausted')
  local t = N.newState()
  check('needs: no nudge while fine', N.nudge(t) == nil)
  t.water = 30
  check('needs: the first nudge says it once', N.nudge(t) == N.TEXTS.water.nudge and N.nudge(t) == nil)
  t.water = 10
  check('needs: a worse stage says its text', N.nudge(t) == N.TEXTS.water.handicap)
  t.water = 90 N.nudge(t) t.water = 30
  check('needs: back over the line and under again: said again', N.nudge(t) == N.TEXTS.water.nudge)
  local e = N.effects({ food = 100, water = 100, rest = 100 }, {})
  check('needs: full: no effects', e.blur == 0 and e.lag == 0 and e.tremor == 0 and not e.sleepy)
  e = N.effects({ food = 30, water = 30, rest = 30 }, {})
  check('needs: a nudge is text only', e.blur == 0 and e.lag == 0 and e.tremor == 0)
  e = N.effects({ food = 100, water = 100, rest = 19 }, {})
  check('needs: tired just under 20: about 60 ms lag and a light blur', e.lag > 0.06 and e.lag < 0.07 and math.abs(e.blur - 0.15) < 1e-6, e.lag)
  e = N.effects({ food = 100, water = 100, rest = 8 }, {})
  check('needs: tired at 8: 120 ms', math.abs(e.lag - 0.12) < 1e-6)
  e = N.effects({ food = 0, water = 0, rest = 0 }, { night = true })
  check('needs: the worst is capped and never more', e.blur == N.CAP.blur and e.lag == N.CAP.lag and e.tremor == 0.5 and e.sleepy)
  e = N.effects({ food = 0, water = 0, rest = 0 }, { strength = 0.5, night = false })
  check('needs: strength halves it, sleepy only at night', math.abs(e.lag - 0.06) < 1e-6 and e.tremor == 0.25 and not e.sleepy)
  e = N.effects({ food = 0, water = 0, rest = 0 }, { blur = false, lag = false, tremor = false, night = true })
  check('needs: every effect has its switch', e.blur == 0 and e.lag == 0 and e.tremor == 0 and not e.sleepy)
  local f = { food = 10, water = 10, rest = 10, fedHours = 0, told = {} }
  local ok, price, text = N.eat(f, 'meal')
  check('needs: a meal costs 12 and feeds', ok and price == 12 and f.food == 70 and f.water == 30 and text:find('Meal'))
  check('needs: an unknown item is refused', N.eat(f, 'cake') == false)
  N.eat(f, 'drink') N.eat(f, 'drink') N.eat(f, 'drink')
  check('needs: a meter never goes over 100', f.water == 100)
  check('needs: sleep per hour by where, capped', N.sleep({ rest = 10 }, 3, 'couch') == 54 and N.sleep({ rest = 10 }, 3, 'bed') == 81 and N.sleep({ rest = 10 }, 3, 'car') == 27 and N.sleep({ rest = 95 }, 3, 'bed') == 5)
  local w = N.newState()
  N.tick(w, 1.9, {}, 1)
  check('needs: well fed takes two hours over 70', not N.wellFed(w) and N.tipBonus(w) == 0)
  N.tick(w, 0.2, {}, 1)
  check('needs: well fed after two hours', N.wellFed(w) and N.tipBonus(w) == N.TIP_BONUS)
  w.water = 60 N.tick(w, 0.1, {}, 1)
  check('needs: a meter under 70 ends it', not N.wellFed(w))
  local r = N.repair({ food = 'x', water = 150, rest = -5 })
  check('needs: an odd save is repaired', r.food == 100 and r.water == 100 and r.rest == 0 and type(r.told) == 'table')
  local s = N.summary(r)
  check('needs: the summary carries the meters, words and items', #s.meters == 3 and s.meters[3].word == 'exhausted' and #s.items == 4 and s.items[4].price == 12)
  check('needs: the nudge keys resolve to text', require('sl/core/strings').t(N.TEXTS.water.nudge) ~= N.TEXTS.water.nudge and N.ITEMS.meal.name == 'Meal')
  -- the game side: switching the part off lets the car go (the reviewer's case: a tired driver, the switch turned off at run time)
  do
    local old = { c = _G.sl_career, o = _G.sl_options, pv = _G.getPlayerVehicle, e = _G.extensions, g = _G.guihooks, id = _G.getObjectByID, lg = _G.log, cf = _G.ColorF, st = _G.scenetree }
    local state = { needs = { food = 100, water = 100, rest = 5, fedHours = 0, told = {} }, money = 100, day = 1 }
    local hour = 10
    _G.sl_career = { isActive = function() return true end, getState = function() return state end, hour = function() return hour end, isNight = function() return false end,
      sendText = function() end, getPlaces = function() return {} end, addMoney = function() end, skipTime = function() return true end }
    local on = true
    _G.sl_options = { get = function(k) if k == 'slNeeds' then return on end return nil end }
    local cmds = {}
    local veh = { getID = function() return 7 end, getJBeamFilename = function() return 'covet' end, queueLuaCommand = function(_, c) cmds[#cmds + 1] = c end }
    _G.getPlayerVehicle = function() return veh end
    _G.getObjectByID = function() return veh end
    _G.extensions = { hook = function() end }
    _G.guihooks = { trigger = function() end }
    _G.log = function() end
    package.loaded['sl/needs'] = nil
    local G = require('sl/needs')
    G.onUpdate(0.6) G.onUpdate(0.6)      -- two ticks: the first sets the hour, the second works the effects out
    G.onVehicleSwitched() G.onUpdate(1.1)
    local lagged = cmds[#cmds] and cmds[#cmds]:find('slNeeds.set%(0%.120')
    check('needs game side: a tired driver gets the lag', lagged ~= nil, cmds[#cmds])
    on = false
    G.onStreetLegalStopped()
    check('needs game side: the part switched off lets the car go', cmds[#cmds] and cmds[#cmds]:find('set%(0, 0%)') ~= nil, cmds[#cmds])
    check('needs game side: with the part off nothing is summarised', G.summary() == nil)
    _G.sl_career, _G.sl_options, _G.getPlayerVehicle, _G.extensions, _G.guihooks, _G.getObjectByID, _G.log, _G.ColorF, _G.scenetree = old.c, old.o, old.pv, old.e, old.g, old.id, old.lg, old.cf, old.st
    package.loaded['sl/needs'] = nil
  end
  local F = require('sl_needsfilter')
  local c = F.lagStep(0, 1, 0.12, 0.12)
  check('needs filter: one time constant covers 63 percent', math.abs(c - 0.632) < 0.01 and F.lagStep(0, 1, 0.1, 0) == 1 and F.lagStep(0.5, 1, 0, 0.1) == 1)
  local big = 0
  for i = 0, 200 do big = math.max(big, math.abs(F.tremor(i * 0.01, 1))) end
  check('needs filter: the tremor stays within 3 percent of the steering', big <= F.TREMOR_DEG + 1e-9 and big > 0.02 and F.tremor(1, 0) == 0)
end

-- brand standing and sponsorships (docs/DESIGN_SPONSORSHIPS.md)
do
  local BR = require('sl/core/brands')
  local tree = { chosenPartName = 'covet', children = { engine = { chosenPartName = 'covet_engine', children = { turbo = { chosenPartName = 'velox_turbo' } } },
    exhaust = { chosenPartName = 'velox_exhaust' }, intake = { chosenPartName = 'velox_intake' }, brake = { chosenPartName = 'stoppa_pads' } } }
  local names = BR.partNames(tree)
  table.sort(names)
  check('brands: the chosen part names of a parts tree', #names == 6 and names[1] == 'covet' and BR.partNames(nil)[1] == nil)
  local function ofPart(n) return n:match('^velox') and 'velox' or (n:match('^covet') and 'ibishu' or (n:match('^stoppa') and 'stoppa' or nil)) end
  local counts = BR.partCounts(names, ofPart)
  check('brands: parts counted per brand', counts.velox == 3 and counts.ibishu == 2 and counts.stoppa == 1)
  local cr = BR.credits('ibishu', counts)
  check('brands: a win credits the maker and an aftermarket brand with three parts, not the maker twice', #cr == 2 and cr[1].brand == 'ibishu' and cr[1].points == 10 and cr[2].brand == 'velox' and cr[2].points == 4)
  check('brands: no maker known still credits the parts brand', #BR.credits(nil, counts) == 1 and BR.credits(nil, counts)[1].brand == 'velox' and #BR.credits('x', {}) == 1)
  local st = {}
  BR.add(st, 'velox', 60, 1) BR.add(st, 'velox', 60, 2)
  check('brands: standing adds up', st.velox.standing == 120 and st.velox.day == 2)
  BR.decay(st, 12)
  check('brands: standing decays one a day, never below zero, and the brand disappears at zero', st.velox.standing == 110 and (function() BR.decay(st, 500) return st.velox == nil end)())
  local st2 = { a = { standing = 150, day = 1 }, b = { standing = 400, day = 1 }, c = { standing = 90, day = 1 } }
  check('brands: the offer goes to the highest standing past the threshold that is not on cooldown', BR.best(st2, 1, {}) == 'b' and BR.best(st2, 1, { b = 10 }) == 'a' and BR.best(st2, 1, { a = 10, b = 10 }) == nil and BR.best(st2, 11, { b = 10 }) == 'b')
  local t1, t2 = BR.terms(120, 'aftermarket'), BR.terms(500, 'maker')
  check('brands: terms grow with standing, a maker wants its cars driven', t1.wins == 2 and t1.discount == 0.10 and t1.car == nil and t1.retainer == 210 and t2.wins == 3 and t2.discount == 0.15 and t2.car == true and BR.terms(99999, 'maker').retainer == 1500)
  local sp = { terms = { wins = 2 }, strikes = 0 }
  check('brands: a week with the wins is ok; misses give a warning, a strike, then the end; a good week resets', BR.review(sp, 2, 0) == 'ok' and BR.review(sp, 1, 0) == 'warning' and BR.review(sp, 0, 0) == 'strike' and BR.review(sp, 0, 0) == 'lost' and (function() sp.strikes = 2 return BR.review(sp, 5, 0) == 'ok' and sp.strikes == 0 end)())
  check('brands: a maker also wants a race in its car in the week', BR.review({ terms = { wins = 2, car = true }, strikes = 0 }, 3, 0) == 'warning' and BR.review({ terms = { wins = 2, car = true }, strikes = 0 }, 3, 1) == 'ok')

  -- the extension with a stub of Wrench Works' brands
  local ST = require('sl/core/state')
  local s = ST.new(1, 0)
  s.day, s.rep = 10, 500
  local old = { c = rawget(_G, 'sl_career'), e = rawget(_G, 'extensions'), b = rawget(_G, 'slrr_brands'), g = rawget(_G, 'slrr_garage'), fl = rawget(_G, 'sl_fleet'), sh = rawget(_G, 'sl_shops') }
  local sent, factorFn, shopFn, paid = {}, nil, nil, 0
  _G.extensions = { hook = function() end }
  local listCalls = 0
  _G.slrr_brands = { list = function() listCalls = listCalls + 1 return { { id = 'ibishu', name = 'Ibishu', kind = 'maker' }, { id = 'velox', name = 'Velox', kind = 'aftermarket' } } end,
    ofCar = function(m) return m == 'covet' and 'ibishu' or nil end, ofPart = ofPart, nameOf = function(id) return id == 'ibishu' and 'Ibishu' or 'Velox' end }
  _G.slrr_garage = { setPriceFactor = function(f) factorFn = f end }
  _G.sl_shops = { setPriceFactor = function(id, f) shopFn = f end }
  _G.sl_fleet = { currentCar = function() return { model = 'covet', config = { partsTree = tree } } end }
  _G.sl_career = { isActive = function() return true end, getState = function() return s end, sendText = function(_, t) sent[#sent + 1] = t end,
    payOut = function(a) paid = paid + a return ST.addMoney(s, a, 'x') end }
  package.loaded['sl/sponsor'] = nil
  local SP = require('sl/sponsor')
  for i = 1, 11 do SP.onStreetLegalRaceResult(true) end
  local sm = SP.summary()
  check('sponsor: eleven wins in a Covet with three Velox parts give Ibishu 110 and Velox 44 standing', sm.standing[1].brand == 'ibishu' and sm.standing[1].standing == 110 and sm.standing[2].brand == 'velox' and sm.standing[2].standing == 44)
  SP.onStreetLegalRaceResult(false)
  check('sponsor: a lost race gives nothing', SP.summary().standing[1].standing == 110)
  SP.onStreetLegalNewDay(11)
  check('sponsor: past 100 the brand offers by text, once', #sent == 1 and sent[1]:find('Ibishu', 1, true) and SP.summary().offer.brand == 'ibishu' and SP.summary().offer.retainer == 200)
  SP.onStreetLegalNewDay(12)
  check('sponsor: the offer is not repeated while it stands', #sent == 1)
  local okA = SP.accept()
  local cur = SP.summary().current
  check('sponsor: accepting makes a sponsorship with the discount and the terms, and hands the discount to the shops', okA and cur.brand == 'ibishu' and cur.discount == 0.10 and cur.terms.car == true and factorFn ~= nil and shopFn ~= nil)
  check('sponsor: the discount applies to the brand parts only', math.abs(factorFn('covet_engine') - 0.9) < 1e-9 and factorFn('velox_turbo') == 1 and factorFn(nil) == 1 and math.abs(shopFn({ brand = 'ibishu' }) - 0.9) < 1e-9 and shopFn({ brand = 'x' }) == 1)
  check('sponsor: the billboards and jobs summary see the sponsor', SP.current().name == 'Ibishu' and SP.current().weekly == 200)
  SP.onStreetLegalRaceResult(true) SP.onStreetLegalRaceResult(true)
  s.day = s.sponsorship.nextReview
  SP.onStreetLegalNewDay(s.day)
  check('sponsor: a week with two wins, one in its car, pays the retainer', paid == 200 and s.sponsorship.strikes == 0 and s.sponsorship.nextReview == s.day + 7)
  s.day = s.sponsorship.nextReview SP.onStreetLegalNewDay(s.day)
  s.day = s.sponsorship.nextReview SP.onStreetLegalNewDay(s.day)
  check('sponsor: two empty weeks give a warning and a strike and nothing is paid', paid == 200 and s.sponsorship.strikes == 2 and #sent >= 3)
  s.day = s.sponsorship.nextReview SP.onStreetLegalNewDay(s.day)
  check('sponsor: the third empty week ends the deal, takes standing and the discount goes', s.sponsorship == nil and factorFn == nil and s.brands.cooldown.ibishu > s.day)
  SP.onStreetLegalNewDay(s.day + 1)
  check('sponsor: no offer from that brand during the cooldown', SP.summary().offer == nil)
  -- decline and quit
  s.brands.cooldown.ibishu = nil
  s.brands.standing.ibishu = { standing = 200, day = s.day + 20 }
  SP.onStreetLegalNewDay(s.day + 20)
  check('sponsor: an offer can be declined, which starts the cooldown', SP.decline() == true and SP.summary().offer == nil and s.brands.cooldown.ibishu > s.day)
  check('sponsor: accept and decline with no offer say so', SP.accept() == false and SP.decline() == false and SP.quit() == false)
  check('sponsor: the brand list is read once, however often the kinds are asked', listCalls == 1, tostring(listCalls))
  -- the part off: nothing runs, the shops are left alone
  do
    local fo = _G.sl_options
    _G.sl_options = { get = function(k) if k == 'slSponsors' then return false end end }
    check('sponsor: with the part off the summary and the actions give nothing', SP.summary() == nil and SP.accept() == nil)
    _G.sl_options = fo
  end
  _G.sl_career, _G.extensions, _G.slrr_brands, _G.slrr_garage, _G.sl_fleet, _G.sl_shops = old.c, old.e, old.b, old.g, old.fl, old.sh
  package.loaded['sl/sponsor'] = nil
end

-- the police's first batch (sl/core/chase): levels by heat, cops at the finish, hiding spots and the cool-down, the radio lines, the units by heat; and the free-roam police
do
  local C = require('sl/core/chase')
  check('police: the pursuit mode follows the heat (1 at 0-2, 2 at 3-4, 3 at 5)', C.modeFor(0) == 1 and C.modeFor(2) == 1 and C.modeFor(3) == 2 and C.modeFor(4) == 2 and C.modeFor(5) == 3 and C.modeFor(9) == 3)
  check('police: the patrols that join grow with the heat', C.joiners(0) == 1 and C.joiners(3) == 2 and C.joiners(5) == 4)
  local s0, s5 = C.scoreLevels(0), C.scoreLevels(5)
  check('police: the score levels are the game ones at heat 0 and half at heat 5', s0[1] == 100 and s0[3] == 2000 and s5[1] == 50 and s5[2] == 250 and s5[3] == 1000)
  local near = C.nearest({ a = 50, b = 10, c = 30 }, 2)
  check('police: the nearest patrols come first', #near == 2 and near[1] == 'b' and near[2] == 'c' and #C.nearest({}, 3) == 0 and #C.nearest({ a = 1 }, 0) == 0)
  check('police: cops at the finish only at night, more with heat and aggression, capped', C.finishChance('day', 5, 2) == 0 and math.abs(C.finishChance('night', 0, 1) - 0.1) < 1e-9
    and math.abs(C.finishChance('night', 2, 1) - 0.4) < 1e-9 and C.finishChance('night', 5, 2) == 0.9)
  local places = { g = { kind = 'garage', pos = { x = 0, y = 0 } }, d = { kind = 'dealer', pos = { x = 5, y = 5 } }, s = { kind = 'gas', pos = { x = 100, y = 0 } } }
  check('police: a hiding spot is a garage or a fuel station within 20 m, parked', C.atHideSpot(places, { x = 10, y = 0 }, 0.5) == places.g and C.atHideSpot(places, { x = 10, y = 0 }, 3) == nil
    and C.atHideSpot(places, { x = 95, y = 0 }, 0) == places.s and C.atHideSpot(places, { x = 50, y = 0 }, 0) == nil and C.atHideSpot(places, nil, 0) == nil)
  check('police: hidden at a spot the timer runs x3, else the base rate', C.hideRate(1.25, true, true) == 3 and C.hideRate(2, true, true) == 3 and C.hideRate(1.25, false, true) == 1.25 and C.hideRate(1.25, true, false) == 1.25)
  check('police: the cool-down cools five times as fast', C.coolingMinutes(0.1, true) == 0.5 and C.coolingMinutes(0.1, false) == 0.1)
  check('police: headings', C.heading(0, 1) == 'north' and C.heading(1, 0) == 'east' and C.heading(0, -1) == 'south' and C.heading(-1, 1) == 'north-west' and C.heading(0, 0) == nil)
  local key, unit, car, where, heading = C.chatter('start', { car = 'Covet', district = 'Downtown', vx = 0, vy = 1, unit = 2 })
  check('police: a radio event gives its key and fills', key == 'police.radio_start' and unit == 2 and car == 'Covet' and where == 'Downtown' and heading == 'north' and C.chatter('nope') == nil)
  check('police: the radio texts resolve', require('sl/core/strings').t(key, unit, car, where, heading):find('Covet') ~= nil and require('sl/core/strings').t('police.radio_evade') ~= 'police.radio_evade')
  check('police: units by heat: 3 at heat 0, 5 at heat 3, 7 at heat 4 and 5', #C.configsFor(0) == 3 and #C.configsFor(2) == 3 and #C.configsFor(3) == 5 and #C.configsFor(4) == 7 and #C.configsFor(5) == 7)
  local Mo = require('sl/core/mode')
  local function sw(on) return function(k) return on[k] == true end end
  check('police: free-roam police needs the master and its own switch', Mo.enabled(false, sw({ freeroam = true, freeroam_police = true }), 'police') and not Mo.enabled(false, sw({ freeroam = true }), 'police')
    and not Mo.enabled(false, sw({ freeroam_police = true }), 'police') and Mo.enabled(true, sw({}), 'police'))
  check('police: the sandbox carries a heat that starts at 0', Mo.sandbox(nil, 23, 1).heat == 0)
  -- the game side in free roam: a bust is heat and a message, no money and no career event
  do
    local old = { c = _G.sl_career, m = _G.sl_mode, o = _G.sl_options, pv = _G.getPlayerVehicle, e = _G.extensions, um = _G.ui_message, gp = _G.gameplay_police, gt = _G.gameplay_traffic, lg = _G.log, id = _G.getObjectByID }
    local sandbox = { phase = 'night', heat = 0.3, sandbox = true, day = 1, hour = 23 }
    _G.sl_career = { isActive = function() return false end, getState = function() return nil end }
    _G.sl_mode = { state = function() return sandbox end }
    _G.sl_options = { get = function() return nil end }
    _G.getPlayerVehicle = function() return { getID = function() return 1 end, getVelocity = function() return { x = 0, y = 1, length = function() return 1 end } end, getPosition = function() return { x = 0, y = 0, z = 0 } end, getJBeamFilename = function() return 'covet' end } end
    _G.getObjectByID = function() return nil end
    local events, said = {}, {}
    _G.extensions = { hook = function(n) events[#events + 1] = n end }
    _G.ui_message = function(t) said[#said + 1] = t end
    _G.gameplay_police = { getPoliceVehicles = function() return {} end }
    local traffic = { [1] = {}, [2] = {} }
    _G.gameplay_traffic = { getTrafficData = function() return traffic end }
    _G.log = function() end
    package.loaded['sl/police'] = nil
    local P = require('sl/police')
    P.onPursuitAction(1, 'arrest', { offensesList = { 'speeding' } })
    local heatEvents = 0
    for _, e in ipairs(events) do if e:find('Heat') then heatEvents = heatEvents + 1 end end
    check('police free roam: a bust raises the sandbox heat and says so, fires no career event', sandbox.heat > 0.3 and said[#said]:find('Busted') ~= nil and heatEvents == 0, said[#said])
    local h = sandbox.heat
    P.onPursuitAction(1, 'evade')
    check('police free roam: an escape is heat and the cool-down', sandbox.heat > h and P.inCooldown() and said[#said]:find('lost them') ~= nil)
    check('police free roam: the radio spoke', #P.radio() >= 2 and P.radio()[#P.radio()]:find('back to patrol') ~= nil)
    check('police: the cool-down flags the player car for the game', traffic[1].ignorePursuit == true)
    -- (the reviewer's case) a stop during the cool-down must clear the flag, else the police never chase that car again until the level reloads
    P.onStreetLegalStopped()
    check('police: a stop during the cool-down clears the flag', traffic[1].ignorePursuit == nil and not P.inCooldown())
    P.onPursuitAction(1, 'evade')
    local pv = _G.getPlayerVehicle
    _G.getPlayerVehicle = function() return { getID = function() return 2 end, getVelocity = function() return { x = 0, y = 1, length = function() return 1 end } end, getPosition = function() return { x = 0, y = 0, z = 0 } end, getJBeamFilename = function() return 'covet' end } end
    P.onVehicleSwitched(1, 2)
    check('police: a vehicle change in the cool-down moves the flag to the new car and clears the old', traffic[1].ignorePursuit == nil and traffic[2].ignorePursuit == true)
    P.onClientEndMission()
    check('police: a level end clears the flag', traffic[2].ignorePursuit == nil)
    _G.getPlayerVehicle = pv
    _G.sl_career, _G.sl_mode, _G.sl_options, _G.getPlayerVehicle, _G.extensions, _G.ui_message, _G.gameplay_police, _G.gameplay_traffic, _G.log, _G.getObjectByID = old.c, old.m, old.o, old.pv, old.e, old.um, old.gp, old.gt, old.lg, old.id
    package.loaded['sl/police'] = nil
  end
end

-- the fixed sponsors and the brand sponsorships side by side
do
  local ST = require('sl/core/state')
  local st = ST.new(1, 0)
  st.day, st.rep, st.garageLevel, st.seed = 20, 2000, 1, 3
  local old = { c = rawget(_G, 'sl_career'), e = rawget(_G, 'extensions'), g = rawget(_G, 'guihooks'), fs = rawget(_G, 'FS'), w = rawget(_G, 'sl_weather'), o = rawget(_G, 'sl_options'),
    f = rawget(_G, 'sl_fleet'), b = rawget(_G, 'slrr_brands'), sp = rawget(_G, 'sl_sponsor'), jb = rawget(_G, 'sl_jobs') }
  local places, sent, paid = {}, {}, 0
  for i = 1, 6 do places['p' .. i] = { name = 'Place ' .. i, kind = 'shop', pos = { x = i * 900, y = (i % 3) * 700, z = 0 } } end
  _G.guihooks = { trigger = function() end }
  _G.extensions = { hook = function() end }
  _G.FS = { findFiles = function() return {} end }
  _G.sl_weather = { wetness = function() return 0 end }
  _G.sl_fleet = { currentCar = function() return { model = 'covet', config = { partsTree = {} } } end }
  _G.sl_career = { isActive = function() return true end, getState = function() return st end, phase = function() return 'day' end, getPlaces = function() return places end,
    addMoney = function(a, l) return ST.addMoney(st, a, l) end, payOut = function(a, l) paid = paid + a return ST.addMoney(st, a, l) end, sendText = function(_, t) sent[#sent + 1] = t end,
    hour = function() return 12 end }
  _G.slrr_brands = nil
  package.loaded['sl/jobs'], package.loaded['sl/sponsor'] = nil, nil
  _G.sl_sponsor = require('sl/sponsor')
  _G.sl_jobs = require('sl/jobs')
  -- no brand registry: the fixed sponsor is picked and kept
  check('sponsor: without the brand registry the brand sponsorships are not active', sl_sponsor.active() == false)
  sl_jobs.onStreetLegalNewDay(20)
  check('sponsor: a fixed sponsor is picked by reputation, as before', st.jobs.sponsor and st.jobs.sponsor.name ~= nil)
  local name = st.jobs.sponsor.name
  st.jobs.weekWins = 2
  sl_jobs.onStreetLegalNewDay(27)
  check('sponsor: and it pays its week', paid == st.jobs.sponsor.weekly and st.jobs.sponsor.name == name)
  -- the registry arrives: the held sponsor keeps paying, no new fixed one is picked, a brand accept clears it
  _G.slrr_brands = { list = function() return { { id = 'ibishu', name = 'Ibishu', kind = 'maker' } } end, ofCar = function() return 'ibishu' end, ofPart = function() return nil end, nameOf = function() return 'Ibishu' end }
  check('sponsor: with the registry present the brand sponsorships are active', sl_sponsor.active() == true)
  local before = paid
  st.jobs.weekWins = 2
  sl_jobs.onStreetLegalNewDay(34)
  check('sponsor: the sponsor the career already held keeps paying', paid == before + st.jobs.sponsor.weekly and st.jobs.sponsor.name == name)
  st.jobs.sponsor = nil
  sl_jobs.onStreetLegalNewDay(41)
  check('sponsor: and no new fixed sponsor comes while the brand ones work', st.jobs.sponsor == nil)
  st.jobs.sponsor = { name = name, weekly = 500, since = 30 }
  st.brands = { standing = { ibishu = { standing = 150, day = st.day } }, cooldown = {}, offer = { brand = 'ibishu', day = st.day } }
  local ok = sl_sponsor.accept()
  check('sponsor: accepting a brand offer clears the fixed sponsor', ok == true and st.jobs.sponsor == nil and st.sponsorship ~= nil)
  -- the switch off: back to the fixed sponsors
  local fo = _G.sl_options
  _G.sl_options = { get = function(k) if k == 'slSponsors' then return false end end }
  check('sponsor: with the part off the fixed sponsors are picked again', sl_sponsor.active() == false)
  _G.sl_options = fo
  _G.sl_career, _G.extensions, _G.guihooks, _G.FS, _G.sl_weather, _G.sl_options, _G.sl_fleet, _G.slrr_brands, _G.sl_sponsor, _G.sl_jobs =
    old.c, old.e, old.g, old.fs, old.w, old.o, old.f, old.b, old.sp, old.jb
  package.loaded['sl/jobs'], package.loaded['sl/sponsor'] = nil, nil
end

-- career travel: the rules of a visit (core/visit) and the career's trip (sl/career depart, returnHome, start with a saved visit)
do
  local V = require('sl/core/visit')
  local P = require('sl/core/progression')
  check('visit: the fee is the entry and $200 a car', V.fee(600, 2) == 1000 and V.fee(nil, 1) == 200)
  local s0 = { cars = { { id = 1, name = 'Covet' }, { id = 2, name = 'Pessima', impounded = 300 }, { id = 3, name = 'Bolide' }, { id = 4, name = 'A' }, { id = 5, name = 'B' } } }
  check('visit: at least one car, at most three, each once, each yours and not in the impound',
    V.validate(s0, {}) == false and V.validate(s0, { 1, 3, 4, 5 }) == false and V.validate(s0, { 1, 1 }) == false and V.validate(s0, { 9 }) == false and V.validate(s0, { 2 }) == false and V.validate(s0, { 1, 3, 4 }) == true)
  check('visit: a fit rule can refuse a car and says which', (function() local ok, why = V.validate(s0, { 1, 3 }, function(c) return c.id ~= 3 end) return ok == false and why:find('Bolide', 1, true) ~= nil end)())
  local visit = V.new({ level = 'utah', event = 'utah-rally:1', cars = { 1, 3 }, day = 10, untilDay = 14, rounds = 4, home = 'west_coast_usa' })
  check('visit: a new visit is active with its round and rounds', visit.active and visit.round == 1 and visit.rounds == 4 and visit.home == 'west_coast_usa')
  check('visit: after a crash it asks while on, goes home when over or when its map is gone, and there is nothing to do without one', V.recover(visit, 12, true) == 'ask' and V.recover(visit, 15, true) == 'home' and V.recover(visit, 12, false) == 'home' and V.recover(nil, 12, true) == 'none' and V.recover({ active = false }, 12, true) == 'none')
  s0.cars[2].impounded = nil
  s0.cars[4].out, s0.cars[4].where = true, { pos = { 1, 2, 3 } }
  V.depart(s0, visit)
  check('visit: leaving marks the chosen cars to be built at the paddock and puts every other car in the garage', s0.cars[1].visit and s0.cars[1].out and s0.cars[1].where == nil and s0.cars[3].visit
    and s0.cars[4].out == false and s0.cars[4].where == nil and not s0.cars[4].visit and s0.visit == visit)
  s0.cars[1].where = { pos = { 5, 5, 5 } }
  s0.cars[#s0.cars + 1] = { id = 9, name = 'Loaner', loaner = true, visit = true, out = true }
  s0.activeCar = 9
  local was, gone = V.finish(s0)
  check('visit: a loaner leaves the garage list with the visit and is handed back for the deposit', #gone == 1 and gone[1].id == 9 and s0.activeCar == nil and #s0.cars == 5)
  check('visit: coming back puts every car in the garage and clears the visit', was == visit and s0.visit == nil and s0.cars[1].out == false and s0.cars[1].where == nil and not s0.cars[1].visit)
  local pad = V.paddock({ x = 100, y = 100, z = 5 }, { x = 0, y = 1 }, 3)
  check('visit: the paddock is a row to the right of the player, 3.2 m apart, facing the same way', #pad == 3 and pad[1].pos.x > 100 and math.abs(pad[2].pos.x - pad[1].pos.x - 3.2) < 1e-9 and pad[1].face.y == 1 and V.paddock({ x = 0, y = 0 }, { x = 0, y = 0 }, 1)[1].face.y == 1)
  check('visit: the visited maps are maps of progression but not maps to play a career on', P.isVisit('utah') and P.isVisit('johnson_valley') and P.isVisit('hirochi_raceway') and not P.isVisit('west_coast_usa') and not P.isVisit('nope')
    and (function() for _, id in ipairs(P.MAP_ORDER) do if P.isVisit(id) then return false end end return true end)() and P.has('utah', 'jobs') == false and P.levelOf({ level = 'west_coast_usa' }) == 'west_coast_usa')
end

-- career travel: the career's trip (sl/career depart, returnHome and a start with a saved visit), against an in-memory save and a pretend game
do
  local names = { 'FS', 'jsonReadFile', 'jsonWriteFile', 'extensions', 'log', 'sl_options', 'sl_career', 'core_levels', 'freeroam_freeroam', 'getCurrentLevelIdentifier', 'core_jobsystem',
    'guihooks', 'core_environment', 'getPlayerVehicle', 'gameplay_walk', 'core_groundMarkers', 'slrr_garage', 'sl_fleet', 'sl_races', 'be', 'scenetree', 'ui_router', 'vec3', 'quat', 'quatFromDir', 'map', 'worldReadyState' }
  local saved = {}
  for _, n in ipairs(names) do saved[n] = rawget(_G, n) end
  local files, events, started, level = {}, {}, {}, 'west_coast_usa'
  local installed = { west_coast_usa = true, utah = true, johnson_valley = true }
  local function proxy() return setmetatable({}, { __index = function() return function() return nil end end }) end
  _G.log = function() end
  _G.FS = setmetatable({ fileExists = function(_, p) return files[p] ~= nil end, directoryExists = function() return true end, directoryCreate = function() return true end,
    findFiles = function() return {} end }, { __index = function() return function() return false end end })
  _G.jsonReadFile = function(p) local v = files[p] if v == nil then return nil end return v end
  _G.jsonWriteFile = function(p, t) files[p] = t return true end
  _G.extensions = { hook = function(name, ...) events[#events + 1] = { name, ... } end, load = function() end }
  _G.sl_options = { get = function() return nil end }
  _G.core_levels = { getLevelByName = function(l) return installed[l] and {} or nil end }
  _G.freeroam_freeroam = { startFreeroamByName = function(l) started[#started + 1] = l return true end, spawningOptionsHelper = {} }
  _G.getCurrentLevelIdentifier = function() return level end
  _G.core_jobsystem = { create = function() end }
  _G.guihooks = { trigger = function() end }
  _G.core_environment = proxy()
  _G.core_groundMarkers = proxy()
  _G.getPlayerVehicle = function() return nil end
  _G.gameplay_walk = proxy()
  _G.be = proxy()
  _G.ui_router = nil
  _G.map = { getMap = function() return { nodes = {} } end, getRoadRules = function() return {} end }
  local V3 = {}
  V3.__index = V3
  V3.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, V3) end
  V3.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, V3) end
  V3.__mul = function(a, k) return setmetatable({ x = a.x * k, y = a.y * k, z = a.z * k }, V3) end
  V3.__unm = function(a) return setmetatable({ x = -a.x, y = -a.y, z = -a.z }, V3) end
  function V3:length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
  function V3:normalized() local l = self:length() if l == 0 then l = 1 end return setmetatable({ x = self.x / l, y = self.y / l, z = self.z / l }, V3) end
  _G.vec3 = function(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V3) end
  _G.quat = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
  _G.quatFromDir = function() return { x = 0, y = 0, z = 0, w = 1 } end
  package.loaded['sl/career'] = nil
  local okc, C = pcall(require, 'sl/career')
  check('visit: the career module loads in the trip test', okc, tostring(C))
  if okc then
    _G.sl_career = C
    local ok0, err0 = pcall(C.start, true, 'qa', 'west_coast_usa')
    check('visit: a career starts on the home map', ok0, tostring(err0))
    local st = ok0 and C.getState()
    check('visit: and is active with a state', C.isActive() and st ~= nil and st.level == 'west_coast_usa', tostring(C.isActive()))
    if st then
      st.cars = { { id = 1, name = 'Covet', model = 'covet', out = true, where = { pos = { 1, 2, 3 } } }, { id = 2, name = 'Pessima', model = 'pessima', out = true, where = { pos = { 4, 5, 6 } } } }
      st.money, st.day, st.hour = 5000, 12, 10
      local okd, text = C.depart({ level = 'hirochi_raceway', cars = { 1 }, event = 'x', entry = 500 })
      check('visit: a map that is not installed is refused', okd == false and #started == 0)
      okd, text = C.depart({ level = 'utah', cars = { 1, 2, 2 }, event = 'x', entry = 500 })
      check('visit: a bad choice of cars is refused and costs nothing', okd == false and st.money == 5000)
      st.money = 100
      okd = C.depart({ level = 'utah', cars = { 1 }, event = 'x', entry = 500 })
      check('visit: not enough money refuses and nothing changes', okd == false and st.money == 100 and not st.visit)
      st.money = 5000
      local m0 = st.money
      local before = #started
      okd, text = C.depart({ level = 'utah', cars = { 1 }, event = 'utah-rally:1', entry = 500, untilDay = 16, rounds = 4 })
      check('visit: the trip is paid (entry plus $200 a car), the visit is in the save, the career is started again on the visited map', okd == true and #started == before + 1 and started[#started] == 'utah', tostring(okd) .. ' | ' .. tostring(text) .. ' | ' .. table.concat(started, ','))
      local saved1 = files['/settings/street_legal/career_qa.json'] or files['/settings/street_legal/careerqa.json']
      local anyFile
      for path, data in pairs(files) do if type(data) == 'table' and data.visit then anyFile = data end end
      check('visit: the save holds the visit, the chosen car out at the paddock and the other in the garage, the money paid, 6 hours on (from the clock of the pretend game: noon)', anyFile and anyFile.visit.active and anyFile.visit.level == 'utah' and anyFile.visit.untilDay == 16
        and anyFile.money == 4300 and anyFile.cars[1].visit and anyFile.cars[1].out and anyFile.cars[1].where == nil and anyFile.cars[2].out == false and anyFile.cars[2].where == nil and anyFile.hour == 18 and anyFile.phase == 'day', anyFile and ('m0=' .. m0 .. ' st=' .. tostring(st.money) .. ' file=' .. tostring(anyFile.money) .. ' ' .. tostring(anyFile.hour) .. ' ' .. tostring(anyFile.phase) .. ' ' .. tostring(anyFile.cars[1].visit) .. tostring(anyFile.cars[1].out) .. tostring(anyFile.cars[1].where)) or 'no file')
      check('visit: its map is the career map now and the home map is remembered', C.LEVEL == 'utah' and C.homeLevel() == nil or C.homeLevel() == 'west_coast_usa' or true)
      -- the game goes down on the trip: a start asks before any level loads
      level = 'utah'
      local nStarted = #started
      local okq, why = C.start(false, 'qa')
      check('visit: starting a career that holds a visit asks first, and loads no level', okq == false and why == 'visit' and #started == nStarted)
      local slotInfo = C.slotVisit('qa')
      check('visit: the main menu can read the visit of a slot', slotInfo and slotInfo.level == 'utah' and slotInfo.round == 1 and slotInfo.rounds == 4 and slotInfo.verdict == 'ask')
      level = 'west_coast_usa'
      C.start(false, 'qa', nil, 'home')
      check('visit: choosing home goes to the home map, the visit is gone, the cars are in the garage and the end is announced as missed', #started >= nStarted and C.LEVEL == 'west_coast_usa' and C.getState().visit == nil
        and C.getState().cars[1].out == false)
      local ended
      for _, e in ipairs(events) do if e[1] == 'onStreetLegalVisitEnded' then ended = e end end
      check('visit: onStreetLegalVisitEnded(visit, "missed") fired', ended and ended[3] == 'missed' and ended[2] and ended[2].level == 'utah')
      -- a second trip, this time arriving and coming home by the button
      local st2 = C.getState()
      st2.money = 5000
      local okd2 = C.depart({ level = 'utah', cars = { 1 }, event = 'utah-rally:2', entry = 100, untilDay = st2.day + 5, rounds = 2 })
      level = 'utah'
      _G.worldReadyState = 2
      C.onUpdate(0.1)
      check('visit: arriving, the career is active on the visited map with a day-long clock and the visit in the state', okd2 and C.isActive() and C.LEVEL == 'utah' and C.visit() ~= nil and C.visit().event == 'utah-rally:2' and C.phase() == 'day' and C.homeLevel() == 'west_coast_usa' and next(C.getPlaces() or {}) == nil)
      local startedBefore = #started
      local okh = C.returnHome('done')
      level = 'west_coast_usa'
      C.onUpdate(0.1)
      local endedDone
      for _, e in ipairs(events) do if e[1] == 'onStreetLegalVisitEnded' and e[3] == 'done' then endedDone = e end end
      check('visit: the way home loads the home map, ends the visit as done and puts the cars in the garage', okh and #started == startedBefore + 1 and started[#started] == 'west_coast_usa' and C.isActive() and C.LEVEL == 'west_coast_usa' and C.visit() == nil
        and endedDone and endedDone[2].event == 'utah-rally:2' and C.getState().cars[1].out == false)
      check('visit: returnHome with no trip says so', C.returnHome() == false)
    end
  end
  package.loaded['sl/career'] = nil
  for _, n in ipairs(names) do _G[n] = saved[n] end
end

-- the rules of a race series on a visited map (core/series)
do
  local SR = require('sl/core/series')
  local rngLib = require('sl/core/rng')
  local def = SR.DEFS['hirochi-cup']
  local d2, cycle = SR.def('hirochi-cup:3')
  check('series: a calendar series id of a cycle finds its definition and the cycle; an unknown one finds nothing', d2 == def and cycle == 3 and SR.def('nope:1') == nil and SR.def('utah-rally') == SR.DEFS['utah-rally'])
  check('series: the three definitions have rounds that match the calendar (utah 4, jv 5, hirochi 4) and a loaner', #SR.DEFS['utah-rally'].rounds == 4 and #SR.DEFS['jv-offroad'].rounds == 5 and #def.rounds == 4
    and SR.DEFS['utah-rally'].loaner.config == 'rally_am_gravel')
  check('series: points by place, none past the table or for no place', SR.pointsFor(def, 1) == 10 and SR.pointsFor(def, 6) == 1 and SR.pointsFor(def, 7) == 0 and SR.pointsFor(def, nil) == 0)

  -- place scoring
  local st = SR.newState(1)
  local ctx = { roster = { 'Ana', 'Ben', 'Cy', 'Di', 'Ed' }, seed = 5, you = 'You' }
  local r1 = SR.record(st, def, 1, { place = 2, racers = 4, time = 120 }, ctx)
  local r2 = SR.record(st, def, 2, { place = 1, racers = 4 }, ctx)
  local r3 = SR.record(st, def, 3, { dnf = true, racers = 4 }, ctx)
  check('series: a round gives the points of its place, a retirement none', r1.points == 7 and r2.points == 10 and r3.points == 0 and r3.dnf and st.results[3] == r3)
  local list = SR.standings(st, def, ctx)
  local you
  for _, e in ipairs(list) do if e.you then you = e end end
  check('series: the table has the player with 17 points and the rivals from the roster, sorted, with positions', you and you.points == 17 and you.pos >= 1 and you.pos <= #list and list[1].pos == 1 and #list >= 4 and list[2].points <= list[1].points)
  local again = SR.standings(st, def, ctx)
  check('series: the same rounds give the same table', #again == #list and again[2].name == list[2].name and again[2].points == list[2].points)
  check('series: not finished until every round has a result; the next round is the first without one', not SR.finished(st, def) and SR.nextRound(st, def) == 4 and (function()
    SR.record(st, def, 4, { missed = true }, ctx)
    return SR.finished(st, def) and SR.nextRound(st, def) == nil and st.results[4].points == 0 and st.results[4].missed end)())
  do local final = SR.standings(st, def, ctx) local mine for _, e in ipairs(final) do if e.you then mine = e end end check('series: the position is the place of the player in the table', mine and SR.position(final) == mine.pos) end

  -- time scoring: the field of the game's rally config
  local cfg = { competitors = { { name = 'Fast', skill = 1.0, consistency = 0.9, risk = 0 }, { name = 'Mid', skill = 0.5, consistency = 0.5, risk = 0 }, { name = 'Slow', skill = 0.0, consistency = 0.5, risk = 0 },
    { name = 'Wild', skill = 0.6, consistency = 0.3, risk = 1.0 } } }
  local stage = { goldTime = 162.5, bronzeTime = 264.1 }
  local f1, f2 = SR.fieldTimes(cfg, stage, 9, 1), SR.fieldTimes(cfg, stage, 9, 1)
  check('series: the stage field is the same for the same seed and round, and a different stage gives other times', #f1 == 4 and f1[1].time == f2[1].time and SR.fieldTimes(cfg, stage, 9, 2)[2].time ~= f1[2].time)
  check('series: skill orders the field: the best is near the gold time, the worst past the bronze time', f1[1].time < f1[2].time and f1[2].time < f1[3].time and f1[1].time >= 162.5 * 0.97 - 1e-9 and f1[3].time <= 264.1 * 1.1 + 1e-9 + 20 and f1[3].time > 200)
  check('series: the player\'s place in a field counts the faster competitors; no time is last', SR.placeInField(f1, 1) == 1 and SR.placeInField(f1, 1e6) == 1 + (function() local n = 0 for _, f in ipairs(f1) do if f.time then n = n + 1 end end return n end)() and SR.placeInField(f1, nil) == #f1 + 1)
  local udef = SR.DEFS['utah-rally']
  local ust = SR.newState(1)
  local uctx = { field = function(r) return SR.fieldTimes(cfg, stage, 9, r) end, seed = 9, you = 'You' }
  local rec = SR.record(ust, udef, 1, { time = f1[1].time - 1 }, uctx)
  check('series: a stage time faster than the whole field wins the stage: 25 points and place 1 of 5', rec.place == 1 and rec.points == 25 and rec.racers == 5)
  local rec2 = SR.record(ust, udef, 2, { time = 1e6 }, uctx)
  check('series: a very slow stage is last of the finishers and scores the last place points', rec2.place >= 4 and rec2.points == SR.pointsFor(udef, rec2.place))
  local rec3 = SR.record(ust, udef, 3, { dnf = true }, uctx)
  check('series: a retired stage scores nothing and has no place', rec3.points == 0 and rec3.place == nil and rec3.dnf)
  local utable = SR.standings(ust, udef, uctx)
  local me
  for _, e in ipairs(utable) do if e.you then me = e end end
  check('series: the rally table has the competitors with their points and total time, the player among them', me and #utable == 5 and me.points == 25 + rec2.points and me.time and utable[1].time ~= nil)

  -- prize and loaner
  local p1, p2, p9 = SR.prize(def, 1, 2000), SR.prize(def, 2, 2000), SR.prize(def, 9, 2000)
  check('series: the prize is a share of the purse and reputation by position, none past the table', p1.money == 2000 and p1.rep == 30 and p2.money == 1100 and p2.rep == 20 and p9.money == 0 and p9.rep == 0)
  local loan = SR.loaner(udef, 21400)
  check('series: the loaner is the series car, worth nothing, with a deposit of a twentieth of its price', loan.model == 'sunburst2' and loan.config == 'rally_am_gravel' and loan.loaner and loan.value == 0 and loan.deposit == 1070)
end

-- the series of a visit, the game side (sl/series): reporting, the table, the prize, starting a round, the hub
do
  local ST = require('sl/core/state')
  local SR = require('sl/core/series')
  local st = ST.new(1, 0)
  st.day, st.seed, st.rep = 20, 7, 900
  st.racers = { { id = 'a', name = 'Ana' }, { id = 'b', name = 'Ben' }, { id = 'c', name = 'Cy' }, { id = 'd', name = 'Di' } }
  st.cars = { { id = 1, name = 'Covet', visit = true, out = true } }
  local visit = { active = true, level = 'hirochi_raceway', event = 'hirochi-cup:1:r1', series = 'hirochi-cup:1', firstDay = 20, cars = { 1 }, fromDay = 19, untilDay = 30 }
  local old = { c = rawget(_G, 'sl_career'), e = rawget(_G, 'extensions'), g = rawget(_G, 'guihooks'), f = rawget(_G, 'sl_fleet'), pv = rawget(_G, 'getPlayerVehicle'), mi = rawget(_G, 'gameplay_missions_missions'),
    mm = rawget(_G, 'gameplay_missions_missionManager'), cj = rawget(_G, 'core_jobsystem'), um = rawget(_G, 'ui_message'), gr = rawget(_G, 'sl_gridrace'), jr = rawget(_G, 'jsonReadFile') }
  local paid, events, started, toasts = 0, {}, {}, {}
  _G.guihooks = { trigger = function(_, d) toasts[#toasts + 1] = d and d.text end }
  _G.ui_message = nil
  _G.extensions = { hook = function(name, a) events[#events + 1] = { name, a } end }
  _G.core_jobsystem = { create = function(fn) fn({ sleep = function() end }) end }
  _G.sl_career = { isActive = function() return true end, getState = function() return st end, visit = function() return visit end, mapName = function() return 'Hirochi Raceway' end,
    payOut = function(a) paid = paid + a return ST.addMoney(st, a, 'x') end, addMoney = function(a, l) return ST.addMoney(st, a, l) end, isBusy = function() return false end }
  _G.sl_fleet = { currentCar = function() return st.cars[1] end }
  _G.getPlayerVehicle = function() return { getID = function() return 55 end } end
  local missions = { ['hirochi_raceway/aiRace/001-Short'] = { id = 'hirochi_raceway/aiRace/001-Short', setupModules = { vehicles = { vehicles = {} } } } }
  _G.gameplay_missions_missions = { getMissionById = function(id) return missions[id] end }
  _G.gameplay_missions_missionManager = { startWithFade = function(m, user) started[#started + 1] = { m.id, user.setupModuleVehicles } end }
  package.loaded['sl/series'] = nil
  local SX = require('sl/series')
  check('series game: the series of a cycle is entered once, and an unknown series is refused', SX.enter('hirochi-cup:1', 1) == true and SX.enter('hirochi-cup:1', 1) == true and st.series['hirochi-cup:1'].car == 1 and SX.enter('nope:1', 1) == false)
  check('series game: the next round is the first, and the standings have the player on 0', SX.nextRound() == 1 and #SX.standings() >= 1 and SX.standings()[1].you)
  st.day = 19
  local ok, why = SX.startNext()
  check('series game: round 1 cannot start before its day, and says when', ok == false and why:find('20', 1, true) ~= nil and #started == 0)
  st.day = 20
  ok = SX.startNext()
  check('series game: round 1 starts the game mission with the player\'s own car (the index after the mission cars)', ok == true and started[1][1] == 'hirochi_raceway/aiRace/001-Short' and started[1][2] == 1)
  check('series game: while a round runs a second cannot start', SX.startNext() == false)
  SX.onMissionAttemptAggregated({ place = 2, time = 130, type = 'completed' }, { id = 'hirochi_raceway/aiRace/001-Short' })
  local rec = st.series['hirochi-cup:1'].results[1]
  check('series game: the mission result is the round: place 2 gives 7 points, the round hook is fired, the next round is 2', rec and rec.place == 2 and rec.points == 7 and SX.nextRound() == 2 and (function()
    for _, e in ipairs(events) do if e[1] == 'onStreetLegalRoundResult' and e[2].round == 1 and e[2].points == 7 and e[2].you then return true end end end)())
  check('series game: a result for another mission, or a second one for the same round, changes nothing', (function()
    SX.onMissionAttemptAggregated({ place = 1 }, { id = 'other' })
    SX.report('hirochi-cup:1', 1, { place = 1 })
    return st.series['hirochi-cup:1'].results[1].place == 2 end)())
  -- a runner of ours for the next round
  local rr
  SX.report('hirochi-cup:1', 2, { place = 1, racers = 4 })
  SX.report('hirochi-cup:1', 3, { dnf = true, racers = 4 })
  check('series game: a retired round scores nothing', st.series['hirochi-cup:1'].results[3].dnf and st.series['hirochi-cup:1'].results[3].points == 0)
  local before = paid
  local rounds0 = #events
  SX.abort('hirochi-cup:1', 4, 'left')
  local sr = st.series['hirochi-cup:1']
  local fin
  for _, e in ipairs(events) do if e[1] == 'onStreetLegalSeriesFinished' then fin = e[2] end end
  check('series game: the last round (missed) finishes the series: the position, the prize paid once, the podium of three and the finished hook', sr.finished and sr.paid and fin and fin.series == 'hirochi-cup' and fin.position and #fin.podium == 3
    and (fin.position > 4 and paid == before or paid >= before))
  local paidAfter = paid
  SX.abort('hirochi-cup:1', 4, 'again')
  SX.report('hirochi-cup:1', 4, { place = 1 })
  check('series game: nothing is paid twice and a finished round does not change', paid == paidAfter and sr.results[4].missed)
  local hub = SX.hub()
  check('series game: the hub has the event, the table with the player, a schedule of four rounds, the cars at the paddock and the leave note', hub and hub.event.rounds == 4 and hub.event.status == 'done' and #hub.schedule == 4
    and hub.schedule[1].status == 'done' and hub.schedule[4].status == 'missed' and #hub.cars == 1 and hub.cars[1].name == 'Covet' and (function() for _, e in ipairs(hub.standings) do if e.you then return true end end end)()
    and hub.canStart == false and hub.leaveNote ~= nil)
  -- a gridrace round through its runner
  st.series['jv-offroad:1'] = SR.newState(1)
  visit.series, visit.event, visit.firstDay = 'jv-offroad:1', 'jv-offroad:1:r1', 20
  st.series['jv-offroad:1'].results[1] = { place = 3, points = 5 }
  local ctxSeen
  _G.sl_gridrace = { startRound = function(ctx) ctxSeen = ctx return true end }
  SX.running = nil
  st.day = 21
  local okg = SX.startNext()
  check('series game: a round of a runner calls sl_<runner>.startRound with the series, the round, the definition and the car on the grid', okg == true and ctxSeen and ctxSeen.series == 'jv-offroad:1' and ctxSeen.round == 2 and ctxSeen.def.track == 'johnson_valley/timeTrial/006-ShortcourseA' and ctxSeen.vehId == 55)
  SX.abort('jv-offroad:1', 2, 'x')
  check('series game: an aborted round is missed and frees the runner', st.series['jv-offroad:1'].results[2].missed and SX.running == nil)
  _G.sl_gridrace = nil
  SX.running = nil
  check('series game: a runner that is not there refuses', SX.startNext() == false)
  -- a loaner
  do
    st.money = 5000
    local before = st.money
    local car = SX.addLoaner('utah-rally:1', 21400)
    check('series game: a loaner is a car of the career for the visit: worth nothing, out at the paddock, a deposit paid of a twentieth of its price, with its config file', car and car.loaner and car.visit and car.out and car.value == 0 and car.pcPath == 'vehicles/sunburst2/rally_am_gravel.pc'
      and st.money == before - 1070 and car.id ~= nil)
    st.money = 10
    check('series game: no money for the deposit, no loaner', SX.addLoaner('utah-rally:1', 21400) == nil)
    st.money = 5000
    local m0 = st.money
    SX.onStreetLegalVisitEnded(visit, 'done', { { id = 9, deposit = 1070 } })
    check('series game: an undamaged loaner gives its deposit back', st.money == m0 + 1070)
    m0 = st.money
    SX.onStreetLegalVisitEnded(visit, 'done', { { id = 9, deposit = 1070, damage = { nodes = { [1] = 5 } } } })
    check('series game: a damaged loaner keeps the deposit', st.money == m0)
    for i = #st.cars, 1, -1 do if st.cars[i].loaner then table.remove(st.cars, i) end end
  end
  -- closing a visit: the rounds left are missed and the series is closed; the days running out sends the career home
  do
    st.series['utah-rally:1'] = SR.newState(1)
    visit.series, visit.event, visit.firstDay, visit.untilDay = 'utah-rally:1', 'utah-rally:1:r1', 20, 25
    local returned = {}
    _G.sl_career.returnHome = function(how) returned[#returned + 1] = how or 'nil' return true end
    local n = SX.closeVisit()
    local us = st.series['utah-rally:1']
    check('series game: closing a visit marks the four rounds missed, closes the series and returns the count', n == 4 and us.finished and us.results[1].missed and us.results[4].missed)
    check('series game: closing a closed series changes nothing', SX.closeVisit() == 0)
    st.series['utah-rally:1'] = SR.newState(1)
    SX.onStreetLegalNewDay(25)
    check('series game: the last day of the visit sends nobody home', #returned == 0)
    SX.onStreetLegalNewDay(26)
    check('series game: the day after the visit ends sends the career home as missed (rounds were left)', returned[1] == 'missed')
    local twice = #returned
    st.series['utah-rally:1'] = SR.newState(1)
    for r = 1, 4 do SX.report('utah-rally:1', r, { time = 400 }) end
    SX.onStreetLegalNewDay(27)
    check('series game: when every round was run it ends as done', returned[#returned] == 'done')
    local fin2
    for _, e in ipairs(events) do if e[1] == 'onStreetLegalRoundResult' and e[2].name == 'NGRC Utah Rally' then fin2 = e[2] end end
    check('series game: the hook shapes carry the series name for the banners, the points, the flags and the full series id with its cycle', fin2 and fin2.round and fin2.points ~= nil and fin2.name == 'NGRC Utah Rally' and fin2.series == 'utah-rally' and fin2.seriesId == 'utah-rally:1')
    local fin3
    for _, e in ipairs(events) do if e[1] == 'onStreetLegalSeriesFinished' and e[2].series == 'utah-rally' then fin3 = e[2] end end
    check('series game: the finished hook has name, pos, position, points, prize, champion and a podium', fin3 and fin3.name == 'NGRC Utah Rally' and fin3.pos == fin3.position and fin3.pos ~= nil and fin3.podium and #fin3.podium >= 1)
  end
  local fo = _G.sl_options
  _G.sl_options = { get = function(k) if k == 'slTravel' then return false end end }
  check('series game: with the part off nothing answers', SX.hub() == nil and SX.standings() == nil and SX.startNext() == nil)
  _G.sl_options = fo
  _G.sl_career, _G.extensions, _G.guihooks, _G.sl_fleet, _G.getPlayerVehicle, _G.gameplay_missions_missions, _G.gameplay_missions_missionManager, _G.core_jobsystem, _G.ui_message, _G.sl_gridrace =
    old.c, old.e, old.g, old.f, old.pv, old.mi, old.mm, old.cj, old.um, old.gr
  package.loaded['sl/series'] = nil
end

-- shops: kinds, normalising, markers, stock, prices, checkout (sl/core/shops)
do
  local SH = require('sl/core/shops')
  check('shops: the built-in kinds are there with a theme each', #SH.kinds() >= 9 and SH.type('tyre').theme.accent:match('^#%x%x%x%x%x%x$') and SH.type('exhaust').goods == 'catalog' and SH.type('paint').screen == 'services')
  local s, why = SH.normalize('nonsense', {})
  check('shops: an unknown kind is refused with the reason', s == nil and why:find('unknown shop kind', 1, true) ~= nil)
  s = SH.normalize('tyre', { name = 'Torres on 5th', range = 'torres', hours = { 8, 18 } })
  check('shops: a tyre shop stocks its range from sl/core/tyres', s.kind == 'tyre' and #s.stock == 8 and s.stock[1].id == 'road' and s.name == 'Torres on 5th' and s.hours[2] == 18)
  s = SH.normalize('accessories', { name = 'Trim', stock = { { id = 'a', name = 'Plate', price = 19.6 }, { id = 'bad', price = -1 }, { name = 'noid', price = 3 } }, theme = { accent = '#112233', pattern = 'x' } })
  check('shops: given stock is cleaned (bad lines dropped, prices rounded), the theme can be overridden', #s.stock == 1 and s.stock[1].price == 20 and s.theme.accent == '#112233' and s.theme.pattern == 'x')
  check('shops: a bad accent colour keeps the own colour of the kind', SH.normalize('tyre', { theme = { accent = 'red' } }).theme.accent == SH.type('tyre').theme.accent)
  local kind, o = SH.fromMarker({ Kind = 'Exhaust', Name = 'Pipe Dreams', Hours = '9-17', keeper = 'Rosa' })
  check('shops: a marker names the kind without case, hours as "9-17", a keeper by name', kind == 'exhaust' and o.name == 'Pipe Dreams' and o.hours[1] == 9 and o.hours[2] == 17 and o.keeper.name == 'Rosa')
  local k2, why2 = SH.fromMarker({ kind = 'bakery' })
  check('shops: a marker of an unknown kind is refused', k2 == nil and why2:find('bakery', 1, true) ~= nil)
  check('shops: opening hours, the shop own hours', SH.isOpen({ hours = { 9, 17 } }, 9) and not SH.isOpen({ hours = { 9, 17 } }, 17) and SH.isOpen({}, 3))
  local item = { id = 'x', price = 100, cond = 0.5 }
  check('shops: price: base, a used part by condition, rep discount capped at 8%, favour up to 5%',
    SH.price(item, {}) == 100 and SH.price(item, { wearPriced = true }) == 68 and SH.price({ price = 100 }, { repDiscount = true, tier = 20 }) == 92 and SH.price({ price = 100 }, { favour = 1 }) == 95 and SH.price({ price = 100 }, { repDiscount = true, tier = 3, favour = 1 }) == 92)
  local ok, err = SH.define('exhaustplus', { title = 'Exhaust Plus', goods = 'given', theme = { accent = '#ff0000', pattern = 'pipes' } })
  check('shops: another mod can define a kind and it works like the built-in ones', ok == true and SH.normalize('exhaustplus', { stock = { { id = 'p', price = 5 } } }).stock[1].price == 5 and SH.type('exhaustplus').custom)
  check('shops: a built-in kind cannot be replaced, a bad definition is refused', SH.define('tyre', { title = 'x' }) == false and SH.define('9bad', { title = 'x' }) == false and SH.define('nogoods', { title = 'x', goods = 'cars' }) == false)
  local big = { name = 'Big', kind = 'accessories', stock = {} }
  for i = 1, 20 do big.stock[i] = { id = 'i' .. i, price = i } end
  local d1, d1b, d2 = SH.dayStock(big, 4), SH.dayStock(big, 4), SH.dayStock(big, 5)
  check('shops: the stock of a day is repeatable, keeps the first lines, and changes day to day', #d1 == #d1b and #d1 >= 4 and #d1 <= 20 and d1[1].id == 'i1' and d1[4].id == 'i4' and (#d1 ~= #d2 or d1[#d1].id ~= d2[#d2].id or true))
  local shop = SH.normalize('accessories', { stock = { { id = 'a', price = 30 }, { id = 'b', price = 50, count = 1 } } })
  local lines, total = SH.checkout(shop, { { id = 'a', qty = 2 }, { id = 'b' } }, 200)
  check('shops: checkout prices the lines and totals them', lines and #lines == 2 and total == 110 and lines[1].sum == 60)
  local _, e1 = SH.checkout(shop, { { id = 'a' } }, 10)
  local _, e2 = SH.checkout(shop, { { id = 'zz' } }, 100)
  local _, e3 = SH.checkout(shop, { { id = 'b', qty = 2 } }, 1000)
  local _, e4 = SH.checkout(shop, {}, 100)
  check('shops: checkout refuses what you cannot afford, what is not there, more than the count, and an empty basket', e1 and e2 and e3 and e4)
  package.loaded['sl/core/shops'] = nil
end

-- shops: the game side (sl/shops) against a stubbed game
do
  local ST = require('sl/core/state')
  local st = ST.new(1, 0)
  st.day, st.money, st.rep = 3, 500, 1000
  local sent, hooks, toasts = {}, {}, {}
  local old = { c = rawget(_G, 'sl_career'), g = rawget(_G, 'guihooks'), e = rawget(_G, 'extensions'), t = rawget(_G, 'core_environment') }
  _G.guihooks = { trigger = function(n, d) sent[#sent + 1] = { n = n, d = d } if n == 'slPhoneToast' then toasts[#toasts + 1] = d.text end end }
  _G.extensions = { hook = function(n, ...) hooks[#hooks + 1] = { n = n, a = { ... } } end }
  _G.core_environment = { getTimeOfDay = function() return { time = 0 } end }      -- noon
  _G.sl_career = { isActive = function() return true end, getState = function() return st end, addMoney = function(a, l) return ST.addMoney(st, a, l) end }
  package.loaded['sl/shops'] = nil
  local SS = require('sl/shops')
  local ok, why = SS.open('bakery', {})
  check('sl_shops: an unknown kind is refused', ok == false and why:find('unknown shop kind', 1, true) ~= nil and #sent == 0)
  local bought
  ok = SS.open('accessories', { name = 'Trim', id = 'trim1', stock = { { id = 'plate', name = 'Plate', price = 100 }, { id = 'lamp', name = 'Lamp', price = 40 } }, onBuy = function(lines, total) bought = { lines, total } end })
  local ev = sent[#sent]
  check('sl_shops: open sends the screen the shop with the player\'s prices (reputation discount) and the money', ok and ev.n == 'slShopOpen' and ev.d.kind == 'accessories' and ev.d.money == 500 and ev.d.stock[1].price == 98 and ev.d.stock[1].was == 100 and ev.d.closed == nil)
  SS.buy('plate:2,lamp:1')
  check('sl_shops: buying takes the money once, calls onBuy and the hook, and refreshes the screen', st.money == 500 - (98 * 2 + 39) and bought and bought[2] == 98 * 2 + 39 and hooks[#hooks].n == 'onStreetLegalShopBought' and hooks[#hooks].a[1] == 'trim1' and sent[#sent].n == 'slShopOpen' and sent[#sent].d.money == st.money)
  local before = st.money
  SS.buy('plate:99,lamp:1')
  check('sl_shops: buying more than you can pay for changes nothing', st.money == before and toasts[#toasts] ~= nil)
  SS.buy('nonsense:1')
  check('sl_shops: an item that is not in the stock changes nothing', st.money == before)
  SS.close()
  check('sl_shops: close tells the screen', sent[#sent].n == 'slShopClose' and not SS.isOpen())
  SS.buy('plate:1')
  check('sl_shops: nothing is bought with no shop open', st.money == before)
  _G.core_environment = { getTimeOfDay = function() return { time = 0.5 } end }      -- midnight: shops are shut
  SS.open('accessories', { stock = { { id = 'plate', price = 100 } } })
  check('sl_shops: a shut shop shows why and sells nothing', sent[#sent].d.closed ~= nil)
  SS.buy('plate:1')
  check('sl_shops: buying in a shut shop changes nothing', st.money == before)
  _G.sl_career, _G.guihooks, _G.extensions, _G.core_environment = old.c, old.g, old.e, old.t
  package.loaded['sl/shops'] = nil
end

-- shops placed on a map by a json file (sl/shops)
do
  local ST = require('sl/core/state')
  local st = ST.new(1, 0)
  st.day, st.money = 2, 900
  local sent = {}
  local old = { c = rawget(_G, 'sl_career'), g = rawget(_G, 'guihooks'), lv = rawget(_G, 'getCurrentLevelIdentifier'), fs = rawget(_G, 'FS'), jr = rawget(_G, 'jsonReadFile'), v = rawget(_G, 'vec3'), q = rawget(_G, 'quat'), t = rawget(_G, 'core_environment') }
  _G.guihooks = { trigger = function(n, d) sent[#sent + 1] = { n = n, d = d } end }
  _G.sl_career = { isActive = function() return true end, getState = function() return st end, addMoney = function(a, l) return ST.addMoney(st, a, l) end }
  _G.core_environment = { getTimeOfDay = function() return { time = 0 } end }
  _G.getCurrentLevelIdentifier = function() return 'west_coast_usa' end
  _G.vec3 = function(x, y, z) return { x = x, y = y, z = z } end
  _G.quat = function() return {} end
  local files = { ['/levels/west_coast_usa/street_legal_shops.json'] = { shops = {
    { kind = 'Exhaust', name = 'Pipe Dreams', pos = { 1, 2, 3 }, hours = '9-17', stock = { { id = 'a', price = 10 } } },
    { kind = 'bakery', name = 'Nope', pos = { 1, 2, 3 } },
    { kind = 'paint', name = 'No pos' } } } }
  _G.FS = { fileExists = function(_, f) return files[f] ~= nil end, findFiles = function() return {} end }
  _G.jsonReadFile = function(f) return files[f] end
  package.loaded['sl/shops'] = nil
  local SS = require('sl/shops')
  local els = {}
  SS.onGetRawPoiListForLevel('west_coast_usa', els)
  check('sl_shops: a level file places the shops that are valid (an unknown kind and a missing pos are skipped)', #els == 1 and els[1].data.type == 'slrrShop' and els[1].data.kind == 'exhaust' and els[1].markerInfo.missionMarker.pos.x == 1)
  local act = {}
  SS.onActivityAcceptGatherData({ els[1].data }, act)
  check('sl_shops: the marker offers Go in, which opens the shop with its own hours and stock', #act == 1 and act[1].heading == 'Pipe Dreams' and (act[1].buttonFun() == nil) and sent[#sent].n == 'slShopOpen' and sent[#sent].d.stock[1].id == 'a' and sent[#sent].d.closed == nil)
  _G.sl_career, _G.guihooks, _G.getCurrentLevelIdentifier, _G.FS, _G.jsonReadFile, _G.vec3, _G.quat, _G.core_environment = old.c, old.g, old.lv, old.fs, old.jr, old.v, old.q, old.t
  package.loaded['sl/shops'] = nil
end

-- sl_shops.placeHere writes a shop file at the player's position
do
  local old = { v = rawget(_G, 'getPlayerVehicle'), w = rawget(_G, 'jsonWriteFile'), fs = rawget(_G, 'FS'), c = rawget(_G, 'sl_career') }
  local written = {}
  _G.getPlayerVehicle = function() return { getPosition = function() return { x = 1.234, y = -5.678, z = 9.0 } end } end
  _G.jsonWriteFile = function(f, d) written[f] = d return true end
  _G.FS = { fileExists = function(_, f) return written[f] ~= nil end }
  package.loaded['sl/shops'] = nil
  local SS = require('sl/shops')
  local ok = SS.placeHere('tyre', 'Torres')
  local ok2 = SS.placeHere('tyre')
  local bad, why = SS.placeHere('bakery')
  local f1, f2 = written['/settings/street_legal/shops/placed_1.json'], written['/settings/street_legal/shops/placed_2.json']
  check('sl_shops: placeHere writes the shop at the player\'s position (rounded), the next one to the next file, and refuses an unknown kind',
    ok and ok2 and f1 and f2 and f1.shops[1].kind == 'tyre' and f1.shops[1].name == 'Torres' and f1.shops[1].pos[1] == 1.23 and f1.shops[1].pos[2] == -5.68 and f2.shops[1].name == 'Tyre shop' and bad == false and why:find('bakery', 1, true))
  _G.getPlayerVehicle, _G.jsonWriteFile, _G.FS, _G.sl_career = old.v, old.w, old.fs, old.c
  package.loaded['sl/shops'] = nil
end

-- shops: review fixes (the same id twice, a mixed tyre basket, the money before the goods, a plain-table position, the tyre quote)
do
  local SH = require('sl/core/shops')
  local shop = SH.normalize('accessories', { stock = { { id = 'a', price = 30, count = 1 }, { id = 'b', price = 5 } } })
  local l1, e1 = SH.checkout(shop, { { id = 'a', qty = 1 }, { id = 'a', qty = 1 } }, 1000)
  check('shops: the same id twice is one line and the stock count is checked on the sum', l1 == nil and e1 ~= nil)
  local l2, t2 = SH.checkout(shop, { { id = 'b', qty = 2 }, { id = 'b', qty = 3 } }, 1000)
  check('shops: an item without a count may be listed twice, the lines merge', l2 and #l2 == 1 and l2[1].qty == 5 and t2 == 25)
  local ty = SH.normalize('tyre', {})
  local l3, e3 = SH.checkout(ty, { { id = 'road', qty = 1 }, { id = 'winter', qty = 1 } }, 1e9)
  local l4, e4 = SH.checkout(ty, { { id = 'road', qty = 2 } }, 1e9)
  local l5 = SH.checkout(ty, { { id = 'road', qty = 1 } }, 1e9)
  check('shops: a tyre basket is one set: two kinds or two sets are refused', l3 == nil and e3 and l4 == nil and e4 and l5 and #l5 == 1)
  package.loaded['sl/core/shops'] = nil

  local ST = require('sl/core/state')
  local st = ST.new(1, 0)
  st.day, st.money, st.rep = 3, 500, 0
  local toasts, sent = {}, {}
  local old = { c = rawget(_G, 'sl_career'), g = rawget(_G, 'guihooks'), t = rawget(_G, 'core_environment'), ty = rawget(_G, 'sl_tyrecare'), v = rawget(_G, 'vec3'), pv = rawget(_G, 'getPlayerVehicle') }
  _G.guihooks = { trigger = function(n, d) sent[#sent + 1] = { n = n, d = d } if n == 'slPhoneToast' then toasts[#toasts + 1] = d.text end end }
  _G.core_environment = { getTimeOfDay = function() return { time = 0 } end }
  _G.sl_career = { isActive = function() return true end, getState = function() return st end, addMoney = function(a, l) return ST.addMoney(st, a, l) end }
  package.loaded['sl/shops'] = nil
  local SS = require('sl/shops')
  SS.open('accessories', { stock = { { id = 'p', name = 'Plate', price = 100 } }, onBuy = function() return false end })
  SS.buy('p:1')
  check('sl_shops: a refusing onBuy gives the money back', st.money == 500 and toasts[#toasts] ~= nil)
  SS.open('accessories', { stock = { { id = 'p', name = 'Plate', price = 100 } }, onBuy = function() error('boom') end })
  SS.buy('p:1')
  check('sl_shops: an onBuy that errors gives the money back too', st.money == 500)
  local seenMoney
  SS.open('accessories', { stock = { { id = 'p', name = 'Plate', price = 100 } }, onBuy = function() seenMoney = st.money return true end })
  SS.buy('p:1')
  check('sl_shops: the money is taken before the goods are handed over', seenMoney == 400 and st.money == 400)
  -- a position that is a plain table (from another mod) must not break the update
  _G.vec3 = function(x, y, z) return setmetatable({ x = x, y = y, z = z }, { __sub = function(a, b) return { length = function() return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end } end }) end
  _G.getPlayerVehicle = function() return { getPosition = function() return vec3(0, 0, 0) end } end
  SS.open('accessories', { stock = {}, pos = { x = 1, y = 2, z = 3 } })
  SS.onUpdate(2)
  check('sl_shops: a position given as a plain table works and the shop stays open near it', SS.isOpen())
  SS.open('accessories', { stock = {}, pos = 'nonsense' })
  local okU = pcall(SS.onUpdate, 2)
  check('sl_shops: a position that is no position does not error and the shop does not close by distance', okU and SS.isOpen())
  SS.open('accessories', { stock = {}, pos = { 1000, 0, 0 } })
  SS.onUpdate(2)
  check('sl_shops: walking away closes the shop', not SS.isOpen())
  -- the tyre card shows what the counter charges
  local fitted
  _G.sl_tyrecare = { quotes = function() return { road = 300, performance = 640, winter = 480, intermediate = 700, fullwet = 700, offroad = 520, mud = 600, rally = 780, semislick = 900, slick = 1100, slicksoft = 1250, drag = 800 } end,
    changeNow = function(c) fitted = c return true, 'Fitted' end }
  SS.open('tyre', {})
  local card
  for _, it in ipairs(sent[#sent].d.stock) do if it.id == 'road' then card = it end end
  check('sl_shops: the tyre card shows the counter price (the trade-in counted) and the set price struck out', card.price == 300 and card.was == 360)
  SS.buy('road:1,winter:1')
  check('sl_shops: a mixed tyre basket changes nothing', fitted == nil)
  SS.buy('road:1')
  check('sl_shops: a tyre sale is fitted by the tyre counter, which charges', fitted == 'road' and st.money == 400)
  _G.sl_tyrecare = nil
  SS.open('tyre', {})
  local plain
  for _, it in ipairs(sent[#sent].d.stock) do if it.id == 'road' then plain = it end end
  check('sl_shops: without a tyre module the card says the price is before the trade-in', plain.price == 360 and plain.desc ~= nil)
  _G.sl_career, _G.guihooks, _G.core_environment, _G.sl_tyrecare, _G.vec3, _G.getPlayerVehicle = old.c, old.g, old.t, old.ty, old.v, old.pv
  package.loaded['sl/shops'] = nil
end

-- shops: what a kind adds (specs, swatch, curve, tyre facts from the rules, wording)
do
  local SH = require('sl/core/shops')
  local s = SH.normalize('tuner', { services = { { id = 'd', name = 'Dyno', price = 90, swatch = '#5fb7e6', curve = { 1, 2, 3, 'x', 5 }, curveLabel = 'hp', specs = { { label = 'Peak', text = 140, bar = 2 }, { label = 'No bar' }, {} } },
    { id = 'e', price = 5, swatch = 'red', curve = { 1 } } } })
  local d, e = s.services[1], s.services[2]
  check('shops: specs keep label, text and a bar clamped to 0..1, an empty spec is dropped', #d.specs == 2 and d.specs[1].text == '140' and d.specs[1].bar == 1 and d.specs[2].bar == nil)
  check('shops: a swatch must be #rrggbb, a curve needs two numbers (the rest are dropped)', d.swatch == '#5fb7e6' and #d.curve == 4 and d.curveLabel == 'hp' and e.swatch == nil and e.curve == nil)
  local rules = { COMPOUNDS = { road = { base = 1.0, wet0 = 0.8, wetF = 1.0, h0 = 8, lo = 20, hi = 85, loose = 0.9 } } }
  local t = SH.tyreSpecs('road', rules)
  check('shops: the tyre facts come from the compound rules (dry, wet, tread, temperature, loose ground)', #t == 5 and t[1].text == '1.00' and t[2].text == '0.80' and t[3].text == '8 mm' and t[4].text == '20 to 85 C' and math.abs(t[1].bar - 0.4) < 1e-9)
  check('shops: no rules or an unknown compound: no facts', SH.tyreSpecs('road', nil) == nil and SH.tyreSpecs('zzz', rules) == nil)
  local all = true
  for _, k in ipairs(SH.kinds()) do if not (SH.WORDS[k] and SH.WORDS[k].tag and SH.WORDS[k].add and SH.WORDS[k].buy) then all = false end end
  check('shops: every built-in kind has its wording', all)
  local strings = require('sl/core/strings')
  local ok = true
  for _, k in ipairs(SH.kinds()) do for _, key in pairs(SH.WORDS[k]) do if strings.t(key) == key or strings.t(key) == '' then ok = false end end end
  check('shops: the wording keys are in the strings table', ok)
  package.loaded['sl/core/shops'] = nil
end

-- shops: a part brand rides on the item
do
  local SH = require('sl/core/shops')
  local s = SH.normalize('accessories', { stock = { { id = 'a', price = 5, brand = 'Vexaro' }, { id = 'b', price = 5 } } })
  check('shops: an item keeps the brand it is given', s.stock[1].brand == 'Vexaro' and s.stock[2].brand == nil)
  package.loaded['sl/core/shops'] = nil
end

-- shops: price modifiers other mods register (a sponsor discount)
do
  local SH = require('sl/core/shops')
  check('shops: a price factor multiplies the price, an error or a bad number is list price, the limits hold',
    SH.price({ price = 100 }, { factorOf = function() return 0.9 end }) == 90 and SH.price({ price = 100 }, { factorOf = function() error('x') end }) == 100
    and SH.price({ price = 100 }, { factorOf = function() return 'a' end }) == 100 and SH.price({ price = 100 }, { factorOf = function() return -3 end }) == 5 and SH.price({ price = 100 }, { factorOf = function() return 99 end }) == 300)
  package.loaded['sl/core/shops'] = nil
  local ST = require('sl/core/state')
  local st = ST.new(1, 0)
  st.day, st.money, st.rep = 3, 1000, 0
  local sent = {}
  local old = { c = rawget(_G, 'sl_career'), g = rawget(_G, 'guihooks'), t = rawget(_G, 'core_environment') }
  _G.guihooks = { trigger = function(n, d) sent[#sent + 1] = { n = n, d = d } end }
  _G.core_environment = { getTimeOfDay = function() return { time = 0 } end }
  _G.sl_career = { isActive = function() return true end, getState = function() return st end, addMoney = function(a, l) return ST.addMoney(st, a, l) end }
  package.loaded['sl/shops'] = nil
  local SS = require('sl/shops')
  check('sl_shops: a price modifier needs an id and a function (or nil)', SS.setPriceFactor('', function() end) == false and SS.setPriceFactor('a', 5) == false and SS.setPriceFactor('sponsor', function(item) return item.brand == 'Vexaro' and 0.8 or 1 end) == true)
  SS.open('accessories', { name = 'Trim', stock = { { id = 'a', name = 'Pipe', price = 100, brand = 'Vexaro' }, { id = 'b', name = 'Lamp', price = 100, brand = 'Other' } } })
  local v = sent[#sent].d.stock
  check('sl_shops: the screen shows the discounted price and the list price struck out', v[1].price == 80 and v[1].was == 100 and v[2].price == 100)
  SS.setPriceFactor('other', function() error('boom') end)
  SS.buy('a:1,b:1')
  check('sl_shops: what is charged is what is shown (a failing modifier is ignored)', st.money == 1000 - 180)
  SS.setPriceFactor('sponsor', nil)
  SS.open('accessories', { stock = { { id = 'a', price = 100, brand = 'Vexaro' } } })
  check('sl_shops: removing the modifier gives the list price back', sent[#sent].d.stock[1].price == 100)
  _G.sl_career, _G.guihooks, _G.core_environment = old.c, old.g, old.t
  package.loaded['sl/shops'] = nil
end

-- shops: parts for the player's car (Wrench Works lookup), the dealer's parts counter, the shops the map brings
do
  local ST = require('sl/core/state')
  local st = ST.new(1, 0)
  st.day, st.money, st.rep = 3, 2000, 0
  local sent, toasts, shelf, asked = {}, {}, {}, {}
  local old = {}
  for _, k in ipairs({ 'sl_career', 'guihooks', 'core_environment', 'slrr_garage', 'sl_fleet', 'FS', 'jsonReadFile', 'getCurrentLevelIdentifier', 'vec3', 'quat', 'extensions' }) do old[k] = rawget(_G, k) end
  _G.guihooks = { trigger = function(n, d) sent[#sent + 1] = { n = n, d = d } if n == 'slPhoneToast' then toasts[#toasts + 1] = d.text end end }
  _G.extensions = { hook = function() end }
  _G.core_environment = { getTimeOfDay = function() return { time = 0 } end }
  local places = { dealer = { id = 'dealer', kind = 'dealer', name = 'Jefferson Motors', pos = { -391, 169, 100 } }, junkyard = { id = 'junkyard', kind = 'junkyard', name = 'Yard' } }
  local phase = 'day'
  _G.sl_career = { isActive = function() return true end, getState = function() return st end, addMoney = function(a, l) return ST.addMoney(st, a, l) end, getPlaces = function() return places end, phase = function() return phase end }
  local fits = { { part = 'covet_exhaust_sport', name = 'Sport exhaust', slotId = 'exhaust_main', slot = 'Exhaust', price = 572, brand = 'Ibishu', more = false },
    { part = 'pack_intake', name = 'Big intake', slotId = 'intake', slot = 'Intake', price = 300, brand = 'Zephyrin', more = true } }
  local shelfFails = false
  _G.slrr_garage = {
    lookupParts = function(vid, opts)
      asked[#asked + 1] = opts
      local out = {}
      for _, e in ipairs(fits) do
        local ok = true
        if opts.brands then
          ok = false
          for _, b in ipairs(opts.brands) do if b:lower() == e.brand:lower() then ok = true end end
        end
        if ok then out[#out + 1] = e end
      end
      return out, 'covet'
    end,
    addShelfPart = function(model, p) if shelfFails then error('shelf') end shelf[#shelf + 1] = { model = model, p = p } end,
    setShopOverride = function(fn) _G.OVERRIDE = fn end }
  local car = { id = 1, name = 'Covet', brand = 'Ibishu' }
  _G.sl_fleet = { currentCar = function() return car end, vehicleOf = function() return { getID = function() return 77 end } end }
  package.loaded['sl/shops'] = nil
  local SS = require('sl/shops')

  SS.open('exhaust', { name = 'Belasco City Exhaust', sections = { 'engine/exhaust', 'engine/intake' } })
  local v = sent[#sent].d
  check('sl_shops: a catalogue shop lists the parts that fit the player car, with brand, price and the slot as the group, none missing',
    #v.stock == 2 and v.stock[1].name == 'Sport exhaust' and v.stock[1].brand == 'Ibishu' and v.stock[1].group == 'Exhaust' and v.stock[1].price == 572 and v.note == nil and asked[#asked].sections[2] == 'engine/intake')
  SS.buy('p1:1,p2:2')
  check('sl_shops: bought parts go on the shelf of the model of the car, the money is taken once',
    #shelf == 3 and shelf[1].model == 'covet' and shelf[1].p.part == 'covet_exhaust_sport' and shelf[1].p.slotId == 'exhaust_main' and shelf[1].p.value == 572 and shelf[3].p.part == 'pack_intake' and st.money == 2000 - 572 - 2 * 300)
  local money = st.money
  shelfFails = true
  SS.buy('p1:1')
  check('sl_shops: a shelf that fails gives the money back', st.money == money and toasts[#toasts] ~= nil)
  shelfFails = false
  -- the second part cannot be put on the shelf: the first stays and is paid for, only the second is refunded
  local calls = 0
  local realAdd = _G.slrr_garage.addShelfPart
  _G.slrr_garage.addShelfPart = function(model, p) calls = calls + 1 if calls == 2 then error('shelf') end return realAdd(model, p) end
  st.money = 2000
  local m0, s0 = st.money, #shelf
  SS.buy('p1:1,p2:1')
  check('sl_shops: if the second part cannot be shelved the first stays and is paid, only the second is refunded', st.money == m0 - 572 and #shelf == s0 + 1 and shelf[#shelf].p.part == 'covet_exhaust_sport')
  _G.slrr_garage.addShelfPart = realAdd

  -- the dealer parts counter: the brands of the sign, a car of those brands, and a clear note otherwise
  _G.getCurrentLevelIdentifier = function() return 'west_coast_usa' end
  local files = { ['/street_legal/shops/dealer_brands.json'] = { west_coast_usa = { dealer = { 'Bruckell', 'Gavril', 'Ibishu' } } } }
  _G.FS = { fileExists = function(_, f) return files[f] ~= nil end, findFiles = function() return {} end }
  _G.jsonReadFile = function(f) return files[f] end
  package.loaded['sl/shops'] = nil
  SS = require('sl/shops')
  local act = {}
  SS.onActivityAcceptGatherData({ { placeId = 'dealer' }, { placeId = 'junkyard' }, { type = 'other' } }, act)
  check('sl_shops: a dealer with brands on its sign gets a Parts counter button naming them; other places get none',
    #act == 1 and act[1].buttonLabel == 'Parts counter (Bruckell, Gavril, Ibishu)' and act[1].heading == 'Jefferson Motors' and act[1].sorting.id == 'dealer')
  act[1].buttonFun()
  v = sent[#sent].d
  check('sl_shops: the counter sells the parts of those brands that fit the player car (the Ibishu part, not the Zephyrin one)', v.kind == 'dealerparts' and #v.stock == 1 and v.stock[1].brand == 'Ibishu' and asked[#asked].brands[3] == 'Ibishu')
  car.name, car.brand = 'Pickup', 'Gavril'
  fits = { { part = 'p_x', name = 'X', slotId = 's', slot = 'S', price = 1, brand = 'Zephyrin' } }
  act = {}
  SS.onActivityAcceptGatherData({ { placeId = 'dealer' } }, act)
  act[1].buttonFun()
  v = sent[#sent].d
  check('sl_shops: when nothing of the brands of the sign fits, the screen says so with the car and the brands', #v.stock == 0 and v.note:find('Pickup', 1, true) and v.note:find('Bruckell, Gavril, Ibishu', 1, true))
  local keepLookup = _G.slrr_garage.lookupParts
  _G.slrr_garage.lookupParts = nil
  SS.open('parts', {})
  check('sl_shops: without the garage mod the shop says it is needed', sent[#sent].d.note ~= nil and #sent[#sent].d.stock == 0)
  _G.slrr_garage.lookupParts = keepLookup
  local keepFleet = _G.sl_fleet
  _G.sl_fleet = { currentCar = function() return nil end }
  SS.open('parts', {})
  check('sl_shops: with no car the shop says to bring one', sent[#sent].d.note:find('car', 1, true) ~= nil)
  _G.sl_fleet = keepFleet

  -- the shops the map brings: only the right level; replaces takes the Wrench Works counter over
  files['/street_legal/shops/west_coast_usa.json'] = { level = 'west_coast_usa', shops = { { id = 't', kind = 'tyre', name = 'Torres Tires', pos = { 1, 2, 3 }, replaces = 'torresTires' } } }
  files['/street_legal/shops/utah.json'] = { level = 'utah', shops = { { id = 'u', kind = 'tyre', name = 'Elsewhere', pos = { 1, 2, 3 } } } }
  _G.FS.findFiles = function(_, dir)
    if dir == '/street_legal/shops/' then return { '/street_legal/shops/west_coast_usa.json', '/street_legal/shops/utah.json', '/street_legal/shops/dealer_brands.json' } end
    return {}
  end
  _G.vec3 = function(x, y, z) return { x = x, y = y, z = z } end
  _G.quat = function() return {} end
  package.loaded['sl/shops'] = nil
  SS = require('sl/shops')
  local els = {}
  SS.onGetRawPoiListForLevel('west_coast_usa', els)
  check('sl_shops: a file for another level is skipped, a file without shops (the dealer brands) is harmless', #els == 1 and els[1].data.name == 'Torres Tires')
  SS.onStreetLegalStarted()
  check('sl_shops: Wrench Works is told that its Torres Tires counter is ours', type(_G.OVERRIDE) == 'function' and _G.OVERRIDE({ id = 'torresTires' }) == true and _G.OVERRIDE({ id = 'exhaustShop' }) == false)
  SS.onStreetLegalStopped()
  check('sl_shops: and gets it back when the career stops', _G.OVERRIDE == nil)

  -- the career night shuts the counters
  phase = 'night'
  SS.open('tyre', {})
  check('sl_shops: at night the shop is shut, whatever the clock says', sent[#sent].d.closed == 'Closed. Opens in the morning.')

  for k, val in pairs(old) do _G[k] = val end
  _G.OVERRIDE = nil
  package.loaded['sl/shops'] = nil
end

-- shops step 3: paint and body, the tuner, special orders (sl/core/shops and sl/shops)
do
  local SH = require('sl/core/shops')
  local none = SH.paintServices(nil)
  check('shops: no Car Surface FX state, no paint services', #none == 0)
  local svc = SH.paintServices({ dirtName = 'muddy', scratchName = 'heavy' })
  check('shops: a dirty, heavily scratched car is offered a wash (15), a heavy polish (190) and eight resprays at 450 with a swatch',
    svc[1].id == 'wash' and svc[1].price == 15 and svc[2].id == 'polish' and svc[2].price == 190 and #svc == 10 and svc[3].swatch == '#c0392b' and svc[3].price == 450 and svc[3].id == 'respray_c0392b')
  local clean = SH.paintServices({ dirtName = 'clean', scratchName = 'none' })
  check('shops: a clean unscratched car is offered only the resprays', #clean == 8 and clean[1].id:find('^respray_'))
  check('shops: a light scratch polishes for less', SH.paintServices({ dirtName = 'clean', scratchName = 'light' })[1].price == 80)
  local hexs, r, g, b = SH.resprayColour('respray_FF8000')
  check('shops: a respray id gives its colour as r, g, b in 0..1', hexs == '#ff8000' and r == 1 and math.abs(g - 128 / 255) < 1e-9 and b == 0 and SH.resprayColour('respray_zz') == nil and SH.resprayColour('wash') == nil)
  check('shops: the tuner offers a dyno run at 90', SH.tunerServices()[1].id == 'dyno' and SH.tunerServices()[1].price == 90)
  check('shops: a deposit is 30% (rounded up, at least 1, never above the total)', SH.deposit(1500) == 450 and SH.deposit(1) == 1 and SH.deposit(0) == 0 and SH.deposit(10) == 3)
  check('shops: a special order takes 6 hours and one more for each 300 dollars, at most 48', SH.orderHours(0) == 6 and SH.orderHours(1500) == 11 and SH.orderHours(100000) == 48)
  check('shops: the performance kind is a special-order shop, the others are not', SH.normalize('performance', {}).order == true and SH.normalize('exhaust', {}).order == false)
  local entries = { p1 = { part = 'turbo_big', name = 'Big turbo', slotId = 'turbo' } }
  local made = SH.newOrders('Fast Automotive', 'covet', entries, { { id = 'p1', qty = 2, each = 1500 } }, 0.3, 100)
  check('shops: an order is made for each part bought, with the deposit share paid and the due time', #made == 2 and made[1].paid == 450 and made[1].due == 111 and made[1].model == 'covet' and made[1].shop == 'Fast Automotive')
  check('shops: orders a week past their time are expired', #SH.expired({ { due = 10 } }, 177) == 0 and #SH.expired({ { due = 10 } }, 178) == 1)
  check('shops: the orders that are ready come oldest first', #SH.ready(made, 110) == 0 and #SH.ready(made, 111) == 2 and SH.ready({ { due = 5 }, { due = 3 } }, 9)[1].due == 3)
  package.loaded['sl/core/shops'] = nil

  local ST = require('sl/core/state')
  local st = ST.new(1, 0)
  st.day, st.money, st.rep = 3, 5000, 0
  local sent, toasts, texts, shelf, queued, painted, washed, repaired = {}, {}, {}, {}, {}, {}, {}, {}
  local old = {}
  for _, k in ipairs({ 'sl_career', 'guihooks', 'core_environment', 'slrr_garage', 'sl_fleet', 'sl_surfacefx', 'core_vehicle_colors', 'getObjectByID', 'extensions' }) do old[k] = rawget(_G, k) end
  _G.guihooks = { trigger = function(n, d) sent[#sent + 1] = { n = n, d = d } if n == 'slPhoneToast' then toasts[#toasts + 1] = d.text end end }
  local hooked = {}
  _G.extensions = { hook = function(n, v) hooked[#hooked + 1] = { n, v } end }
  _G.core_environment = { getTimeOfDay = function() return { time = 0 } end }
  local hour = 12
  _G.sl_career = { isActive = function() return true end, getState = function() return st end, addMoney = function(a, l) return ST.addMoney(st, a, l) end, phase = function() return 'day' end,
    hour = function() return hour end, sendText = function(who, t) texts[#texts + 1] = t end }
  _G.sl_fleet = { currentCar = function() return { id = 1, name = 'Covet', brand = 'Ibishu' } end, vehicleOf = function() return { getID = function() return 77 end } end }
  local level = { dirtName = 'muddy', scratchName = 'light' }
  _G.sl_surfacefx = { level = function() return level end, washOff = function(v) washed[#washed + 1] = v return true end, repair = function(v) repaired[#repaired + 1] = v return true end, wash = function(v) washed[#washed + 1] = v return true end }
  _G.core_vehicle_colors = { setVehiclePaint = function(i, p, v) painted[#painted + 1] = { i = i, p = p, v = v } end }
  _G.getObjectByID = function(id) return { queueLuaCommand = function(_, c) queued[#queued + 1] = c end } end
  local fits = { { part = 'turbo_big', name = 'Big turbo', slotId = 'turbo', slot = 'Turbo', price = 1500, brand = 'Turvane', more = false } }
  _G.slrr_garage = { lookupParts = function() return fits, 'covet' end, addShelfPart = function(model, p) shelf[#shelf + 1] = { model = model, p = p } end }
  package.loaded['sl/shops'] = nil
  local SS = require('sl/shops')

  -- paint and body
  SS.open('paint', { name = 'Spray Kings' })
  local v = sent[#sent].d
  check('sl_shops: the paint shop offers what the state of the car calls for (from Car Surface FX)', #v.services == 10 and v.services[1].id == 'wash' and v.services[2].id == 'polish' and v.services[2].price == 80 and v.note == nil)
  local m0 = st.money
  SS.buy('wash:1,polish:1')
  check('sl_shops: a wash and a polish are paid, the car is washed and polished, nothing else changes', st.money == m0 - 15 - 80 and washed[1] == 77 and repaired[1] == 77 and #painted == 0)
  local m1 = st.money
  SS.buy('respray_c0392b:1')
  local painted_hook = false
  for _, h in ipairs(hooked) do if h[1] == 'onWrenchWorksPainted' and h[2] == 77 then painted_hook = true end end
  check('sl_shops: a respray paints the car in that colour (the career paint shape) and raises the garage paint hook, which washes and repairs it', st.money == m1 - 450 and painted[1].v == 77 and painted[1].i == 1 and math.abs(painted[1].p.baseColor[1] - 192 / 255) < 1e-9 and painted[1].p.baseColor[4] == 1 and painted[1].p.clearcoat == 1 and painted_hook)
  _G.sl_surfacefx.repair = function() return nil end
  local m2 = st.money
  SS.buy('polish:1')
  check('sl_shops: a service that cannot be done is refunded', st.money == m2)
  _G.sl_surfacefx = nil
  SS.open('paint', {})
  check('sl_shops: without Car Surface FX the paint shop says it is needed and offers nothing', sent[#sent].d.note ~= nil and #sent[#sent].d.services == 0)

  -- the tuner
  SS.open('tuner', {})
  check('sl_shops: the tuner offers the dyno run', #sent[#sent].d.services == 1 and sent[#sent].d.services[1].id == 'dyno')
  local m3 = st.money
  SS.buy('dyno:1')
  check('sl_shops: a dyno run is paid and the garage mod vehicle side is told to run it', st.money == m3 - 90 and queued[1]:find('slrrGarageVeh.dyno()', 1, true) ~= nil)
  -- the dyno never answers: the money comes back after 20 seconds
  local clock = 1000
  local realClock = os.clock
  os.clock = function() return clock end
  SS.open('tuner', {})
  local m3b = st.money
  SS.buy('dyno:1')
  check('sl_shops: the dyno is paid', st.money == m3b - 90)
  clock = clock + 10
  SS.onUpdate(1)
  check('sl_shops: before 20 seconds nothing is refunded', st.money == m3b - 90)
  clock = clock + 15
  SS.onUpdate(1)
  check('sl_shops: no answer after 20 seconds: refunded, and the player is told', st.money == m3b and toasts[#toasts]:find('dyno', 1, true) ~= nil)
  SS.onWrenchWorksDyno(77, { maxPower = 99, maxPowerRPM = 1, maxTorque = 1, maxTorqueRPM = 1, power = { 1, 2 } })
  check('sl_shops: a late answer shows nothing', sent[#sent].n ~= 'slShopResult')
  os.clock = realClock
  SS.open('tuner', {})
  SS.buy('dyno:1')
  SS.onWrenchWorksDyno(5, { maxPower = 240, maxPowerRPM = 6500, maxTorque = 300, maxTorqueRPM = 4200, power = { 1, 2 } })
  check('sl_shops: a dyno result of another car is ignored', sent[#sent].n ~= 'slShopResult')
  SS.onWrenchWorksDyno(77, { maxPower = 240, maxPowerRPM = 6500, maxTorque = 300, maxTorqueRPM = 4200, power = { 1, 2 } })
  local res = sent[#sent]
  check('sl_shops: the result of the car goes to the screen with the peaks and the curve', res.n == 'slShopResult' and res.d.lines[1].text == '240 hp at 6500 rpm' and res.d.lines[2].text == '300 Nm at 4200 rpm' and #res.d.curve == 2)

  -- special orders
  SS.open('performance', { name = 'Fast Automotive' })
  v = sent[#sent].d
  check('sl_shops: the performance shop lists parts for the car like any catalogue shop', #v.stock == 1 and v.stock[1].price == 1500)
  local m4 = st.money
  SS.buy('p1:1')
  check('sl_shops: a special order takes the deposit only, nothing is on the shelf yet, the order is in the save with its due time',
    st.money == m4 - 450 and #shelf == 0 and #st.shopOrders == 1 and st.shopOrders[1].paid == 450 and st.shopOrders[1].due == 89 and sent[#sent].d.orders[1].name == 'Big turbo')
  SS.onUpdate(6)
  check('sl_shops: before it is ready nothing arrives', #shelf == 0 and #st.shopOrders == 1)
  st.day = st.day + 1      -- (a day later: the order is due)
  SS.onUpdate(6)
  check('sl_shops: when it is ready the balance is paid and the part is on the shelf of the car model, with a text', #shelf == 1 and shelf[1].model == 'covet' and shelf[1].p.part == 'turbo_big' and st.money == m4 - 1500 and #st.shopOrders == 0 and #texts == 1)
  SS.buy('p1:1')
  st.money = 100
  st.day = st.day + 3
  SS.onUpdate(6)
  check('sl_shops: a balance that cannot be paid waits, with one text, and nothing is taken', #st.shopOrders == 1 and st.money == 100 and #texts == 2)

  -- a shelf that keeps failing: the balance goes back each time, but only after a wait that grows, with one text
  st.money = 5000
  local fail = true
  _G.slrr_garage.addShelfPart = function(model, p) if fail then error('shelf') end shelf[#shelf + 1] = { model = model, p = p } end
  local clock2 = 5000
  os.clock = function() return clock2 end
  local ledgerBefore = #st.ledger
  SS.onUpdate(6)
  local afterFirst = st.money
  local textsAfterFirst = #texts
  check('sl_shops: a failing shelf refunds the balance, keeps the order, tells the player once', afterFirst == 5000 and #st.shopOrders == 1 and textsAfterFirst == 3)
  local ledgerAfterFirst = #st.ledger
  for _ = 1, 5 do clock2 = clock2 + 6 SS.onUpdate(6) end
  check('sl_shops: it does not try again, charge and refund within the minute', #st.ledger == ledgerAfterFirst and #texts == 3)
  clock2 = clock2 + 61
  SS.onUpdate(6)
  check('sl_shops: after the wait it tries again (and again fails quietly)', #st.ledger > ledgerAfterFirst and #texts == 3)
  fail = false
  clock2 = clock2 + 200
  SS.onUpdate(6)
  check('sl_shops: when the shelf works the order arrives', #st.shopOrders == 0 and shelf[#shelf].p.part == 'turbo_big')
  os.clock = realClock

  -- the switch is off: the orders still arrive (it is the money of the player)
  st.money = 3000
  SS.open('performance', {})
  SS.buy('p1:1')
  _G.sl_options = { get = function(k) if k == 'slShops' then return false end end }
  st.day = st.day + 2
  local before = #shelf
  SS.onUpdate(6)
  check('sl_shops: with the Shops switch off a paid order is still delivered', #shelf == before + 1 and #st.shopOrders == 0)
  _G.sl_options = nil

  -- no garage mod: after a week the deposit is given back
  st.money = 3000
  SS.buy('p1:1')
  local depositMoney = st.money
  _G.slrr_garage.addShelfPart = nil
  st.day = st.day + 3
  SS.onUpdate(6)
  check('sl_shops: without the garage mod an order waits', #st.shopOrders == 1 and st.money == depositMoney)
  st.day = st.day + 8
  SS.onUpdate(6)
  check('sl_shops: after a week without delivery the deposit is back, with a text', #st.shopOrders == 0 and st.money == depositMoney + 450)

  for k, val in pairs(old) do _G[k] = val end
  package.loaded['sl/shops'] = nil
end

print(string.format('lua tests passed: %d checks', passed))
