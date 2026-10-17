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
  check('an unknown level or feature falls back to the default map / off', progression.has(nil, 'roc') and not progression.has('slrr_valo_city', 'nothing'))
  check('Valo texts are untouched on Valo City', progression.mapText('King of Valo City. King of Valo!', 'slrr_valo_city') == 'King of Valo City. King of Valo!'
    and progression.titleFor(6000, 'slrr_valo_city') == 'King of Valo City')
  check('Valo texts name West Coast USA there', progression.mapText('King of Valo City. Every crew in Valo.', 'west_coast_usa') == 'King of West Coast USA. Every crew in West Coast USA.'
    and progression.titleFor(6000, 'west_coast_usa') == 'King of West Coast USA' and progression.titleFor(6000) == 'King of Valo City')
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
  sl_fleet = { forecourt = function() return P(0), 'rot' end,
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
  dealers.onUpdate(5)
  check('nothing is built before the delay', #built == 0 and #state.cars == 0)
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
  check('ripples: none when it does not rain, 1 to 3 by intensity', wx.rippleCount(0) == 0 and wx.rippleCount(0.01) == 0 and wx.rippleCount(0.2) == 1 and wx.rippleCount(0.5) == 2 and wx.rippleCount(1) == 3 and wx.rippleCount(5) == 3)
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
    math.abs(wx.keep('sun', dh) - (1 - 0.55 * 0.85)) < 1e-9 and wx.keep('ambient', dh) > 0.6 and wx.keep('ambient', dh) < 0.75 and wx.keep('sun', dh) > 0.5 and wx.keep('sky', 1) == 0.5 and wx.keep('sun', 0) == 1 and wx.keep('sun', 9) == wx.keep('sun', 1))
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

print(string.format('lua tests passed: %d checks', passed))
