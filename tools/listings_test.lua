-- Tests of sl/core/listings (the used parts and cars market, Design 4), called from luatest.lua
return function(check, rngLib)
  local L = require('sl/core/listings')
  local items = { { kind = 'part', name = 'Exhaust', value = 300 }, { kind = 'part', name = 'Turbo', value = 2400 },
    { kind = 'part', name = 'Mirror', value = 25 }, { kind = 'car', name = 'Covet', value = 9000 }, { kind = 'car', name = 'Bolide', value = 180000 } }

  check('MIN_BUY is the cheapest corner of the market', L.MIN_BUY > 0.4 and L.MIN_BUY < 0.7, L.MIN_BUY)

  -- THE LOOP CHECK (fails the build): nothing bought in any channel can be sold again, to an AI buyer or a
  -- bidder or the Wrench Works counter, for what it cost
  local worst, n, scams, tellsOk = -math.huge, 0, 0, true
  for seed = 1, 400 do
    local rng = rngLib.new(seed)
    for _, ch in ipairs({ 'paper', 'app', 'auction' }) do
      for _, it in ipairs(items) do
        local l = L.listing(rng, it, ch, L.demand(rng), seed)
        if l.scam then
          scams = scams + 1
          if #L.tells(l) < 3 then tellsOk = false end        -- every scam shows its tells
        else
          n = n + 1
          local paid = l.floor                                 -- the least it can be had for
          local best = L.resaleCap(it.value, l.condition)      -- the most anyone pays for it again
          for _ = 1, 20 do best = math.max(best, L.buyerOffer(rng, it.value, l.condition)) end
          local bid, cap = paid, L.resaleCap(it.value, l.condition)
          while true do local b = L.nextBid(rng, bid, cap) if not b then break end bid = b end
          best = math.max(best, bid > paid and bid or 0)
          worst = math.max(worst, L.proceeds(best) - paid, math.floor(paid * 0.5) - paid)   -- (counter: half of what was paid)
        end
      end
    end
  end
  check('no buy-and-sell-again loop in any channel', worst < 0, worst)
  check('plenty of listings checked', n > 5000, n)
  check('scams happen on the app, and always show their tells', scams > 0 and tellsOk)

  local rng = rngLib.new(3)
  local l = { ask = 500, floor = 450, item = { value = 1000 }, condition = 0.6 }
  check('the asking price is accepted as asked', select(2, L.haggle(l, 600, 0)) == 500)
  check('at or over the floor: a deal', L.haggle(l, 460, 0) == 'accept')
  local r, price = L.haggle(l, 380, 0)
  check('close: a counter, never under the floor', r == 'counter' and price >= 450 and price <= 500)
  check('far off: declined', L.haggle(l, 100, 0) == 'decline')
  check('after two rounds the seller walks', L.haggle(l, 380, 2) == 'walk')
  for _ = 1, 200 do
    local o = L.buyerOffer(rng, 2000, 0.7)
    if o > L.resaleCap(2000, 0.7) then check('buyers never pay over the cap', false, o) end
  end
  check('lowballers and fair offers both come', true)
  check('a bid goes up in steps, and stops at the cap', L.nextBid(rngLib.new(1), 1000, 1040) == nil)
  check('deposit, delivery and fee', L.deposit(500) == 50 and L.delivery(500) == 70 and L.proceeds(1000) == 950)
  check('job parts cannot be listed', not L.canList({ foreign = true }) and L.canList({ part = 'x' }))
  check('shelf part condition: wear, nearly new, bent', L.condition({ wear = 0.3 }) == 0.7 and L.condition({}) == 0.9 and L.condition({ damaged = true }) == 0.5)
  -- selling a nearly new part to a Revline buyer can beat the Wrench Works counter (half its value), a little
  check('a buyer can pay more than the counter for a nearly new part', L.resaleCap(1000, 1.0) > 500 and L.resaleCap(1000, 1.0) < 600, L.resaleCap(1000, 1.0))
  local honest = { ask = 900, item = { value = 1000 }, condition = 0.7, rating = 4 }
  check('an honest listing shows no tells', #L.tells(honest) == 0)

  -- the game's own dealerships and garages as places (T12): sl/core/stockdealers
  local D = require('sl/core/stockdealers')
  local progression = require('sl/core/progression')
  local market = require('sl/core/market')
  local tr = function(k) return k == 'levels.x.jeff' and 'Jefferson Motors' or k end
  local newF = { whiteList = { Value = { min = 1000 }, Mileage = { min = 10500000, max = 119000000 } } }
  local oldF = { whiteList = { Mileage = { min = 135000000, max = 300000000 } } }
  check('a dealer whose cars start at 50,000 km sells used cars, the others new', D.offerKind(oldF) == 'used' and D.offerKind(newF) == 'dealer' and D.offerKind(nil) == 'dealer')
  check('a translated name is used, an id is read as words', D.nameOf({ id = 'jeffersonmotors', name = 'levels.x.jeff' }, tr) == 'Jefferson Motors'
    and D.nameOf({ id = 'belascoAuto', name = 'levels.x.belasco' }, tr) == 'Belasco Auto' and D.nameOf({ id = 'truckShop' }) == 'Truck Shop')
  local spots = { { x = 10, y = 20, z = 1, dx = 0, dy = 1 }, { x = 14, y = 20, z = 1, dx = 0, dy = 1 } }
  local jeff = D.dealer({ id = 'jeffersonmotors', name = 'levels.x.jeff', filter = newF }, spots, tr)
  check('a stock dealer is a dealer place on its first parking spot with every spot as a display', jeff.kind == 'dealer' and jeff.id == 'stock_jeffersonmotors'
    and jeff.pos[1] == 10 and jeff.display[2] == 20 and #jeff.displays == 2 and jeff.displays[2].pos[1] == 14 and jeff.stock.kind == 'dealer' and jeff.stock.filter == newF)
  check('a dealer without a parking spot has no place', D.dealer({ id = 'x' }, {}, tr) == nil and D.dealer({ id = 'x' }, nil, tr) == nil)
  local gar = D.garage({ id = 'servicestationGarage' }, {}, { x = 5, y = 6, z = 0 }, tr)
  check('a garage without a spot is placed at its door; with nothing it has no place', gar.kind == 'garage' and gar.pos[1] == 5 and D.garage({ id = 'g' }, {}, nil, tr) == nil)
  local quarry = D.dealer({ id = 'quarrysideAutoSales', filter = oldF }, { { x = 900, y = 900, z = 0, dx = 1, dy = 0 } }, tr)
  -- the map's Jefferson Motors (60 m away) is the stock one: it takes the map's id, "dealer"; the junkyard stays
  local mine = { { id = 'dealer', kind = 'dealer', name = 'Jefferson Motors', pos = { 40, 70, 0 } }, { id = 'junkyard', kind = 'junkyard', name = 'Wrecks', pos = { 12, 22, 0 } },
    { id = 'dealer2', kind = 'dealer', name = 'Far Dealer', pos = { 5000, 5000, 0 } } }
  local merged = D.merge({ jeff, quarry }, mine)
  local byId = {}
  for _, p in ipairs(merged) do byId[p.id] = p end
  check('stock dealers win where they are the same dealer and keep the map place id', byId.dealer == jeff and #merged == 4 and not byId.stock_jeffersonmotors)
  check('the junkyard and a far-away map dealer stay; an unrelated stock dealer is untouched', byId.junkyard and byId.dealer2 and byId.dealer2.name == 'Far Dealer' and byId.stock_quarrysideautosales == quarry)
  local near = D.merge({ D.dealer({ id = 'other', name = 'k' }, { { x = 0, y = 0, z = 0, dx = 0, dy = 1 } }, tr) }, { { id = 'dealer', kind = 'dealer', name = 'Elsewhere Cars', pos = { 30, 40, 0 } } })
  check('a map dealer within 80 m of a stock dealer is the same dealer, whatever its name', #near == 1 and near[1].id == 'dealer')
  check('a map place that is not a dealer is never merged away', #D.merge({ jeff }, { { id = 'j', kind = 'junkyard', name = 'Jefferson Motors', pos = { 10, 20, 0 } } }) == 2)
  -- a dealer's stock: the cars that pass its filter; too few and it is every car
  local cars = {}
  for i = 1, 12 do cars[i] = { model = 'm' .. i, config = 'c' .. i, name = 'Car ' .. i, brand = 'B', value = i * 1000, raw = { Value = i * 1000 } } end
  local passes = function(c, f) return c.raw.Value >= f.whiteList.Value.min end
  check('the pool is the cars that pass the dealer filter', #D.pool(cars, { whiteList = { Value = { min = 6000 } } }, passes) == 7)
  check('a filter that leaves fewer than MIN_POOL cars gives every car', #D.pool(cars, { whiteList = { Value = { min = 11000 } } }, passes) == 12
    and #D.pool(cars, { whiteList = { Value = { min = 99000 } } }, passes) == 12)
  check('no filter, no test or a test that errors gives every car', #D.pool(cars, nil, passes) == 12 and #D.pool(cars, { a = 1 }, nil) == 12
    and #D.pool(cars, { a = 1 }, function() error('x') end) == 12)
  -- priced with the existing rules: a stock dealer's new cars cost what the dealer's always did, used ones the used rules
  local pool = D.pool(cars, { whiteList = { Value = { min = 6000 } } }, passes)
  local newOffers = market.offers(pool, 'dealer', '7:' .. jeff.id, 3, 4)
  local ok = #newOffers == 4
  for _, o in ipairs(newOffers) do ok = ok and o.value >= 6000 and o.price >= o.value and o.price <= o.value * 1.7 + 50 end
  check('a stock dealer sells only cars from its pool at the dealer prices', ok)
  local first, differ = market.offers(pool, 'dealer', '7:a', 3, 4)[1].config, false
  for _, id in ipairs({ 'b', 'c', 'd', 'e', 'f', 'g' }) do differ = differ or market.offers(pool, 'dealer', '7:' .. id, 3, 4)[1].config ~= first end
  check('stock dealers (seeded by their place) do not all show the same cars', differ)
  -- the facilities API stubbed: West Coast USA reads it, Valo City does not
  local calls = 0
  local api = {
    list = function(kind)
      calls = calls + 1
      if kind == 'dealership' then
        return { { id = 'jeffersonmotors', name = 'levels.x.jeff', filter = newF }, { id = 'apmStarterVehicles', remotePurchaseOnly = true }, { id = 'noLot' } }
      end
      return { { id = 'alderDragwayGarage' }, { id = 'servicestationGarage' }, { id = 'nowhereGarage' } }
    end,
    spots = function(f) return (f.id == 'jeffersonmotors' or f.id == 'servicestationGarage') and spots or {} end,
    door = function(f) return nil end,
  }
  local wc = D.fromFacilities(api, 'west_coast_usa', tr)
  local ids = {}
  for _, p in ipairs(wc) do ids[p.id] = p end
  check('West Coast USA: its dealer with a lot and a garage with a spot become places',
    #wc == 2 and ids.stock_jeffersonmotors and ids.stock_jeffersonmotors.kind == 'dealer' and ids.stock_servicestationgarage and ids.stock_servicestationgarage.kind == 'garage')
  check('the tutorial seller, a dealer without a lot, a Wrench Works garage and a garage with no position are left out',
    not ids.stock_apmstartervehicles and not ids.stock_nolot and not ids.stock_alderdragwaygarage and not ids.stock_nowheregarage)
  -- a stock garage beside a Wrench Works garage site is that garage (the ids differ, the building is the same)
  local garApi = {
    list = function(kind) return kind == 'garage' and { { id = 'servicestationGarage' }, { id = 'farGarage' } } or {} end,
    spots = function(f) return f.id == 'servicestationGarage' and { { x = 904.5, y = -546.3, z = 0, dx = 0, dy = 1 } } or { { x = 3000, y = 3000, z = 0, dx = 0, dy = 1 } } end,
    door = function() return nil end,
    ownSpots = function() return { { x = 920, y = -540 }, { x = -50, y = 10 } } end,
  }
  local gs = D.fromFacilities(garApi, 'west_coast_usa', tr)
  check('a stock garage within 30 m of a Wrench Works site is skipped, a far one is kept', #gs == 1 and gs[1].id == 'stock_fargarage')
  garApi.ownSpots = function() return { { x = 940, y = -540 } } end
  check('...and one 40 m from the site is its own garage', #D.fromFacilities(garApi, 'west_coast_usa', tr) == 2)
  garApi.ownSpots = nil
  check('no site list: nothing is skipped', #D.fromFacilities(garApi, 'west_coast_usa', tr) == 2)
  -- the facilities not loaded yet at the first load: no places and a retry; there at the second: the places, no retry
  local st, there = {}, nil
  local function make() return there, tr end
  check('facilities absent at the first load: no stock places, and ask again', #D.load(st, 'west_coast_usa', make) == 0 and st.retry == true)
  there = api
  check('facilities there at the second load: the stock places appear and the asking stops', #D.load(st, 'west_coast_usa', make) == 2 and st.retry == false)
  local st2 = {}
  for _ = 1, D.MAX_TRIES do D.load(st2, 'west_coast_usa', function() return nil end) end
  check('asking stops after MAX_TRIES', st2.retry == false and st2.tries == D.MAX_TRIES)
  check('Valo City never asks again', #D.load({}, 'slrr_valo_city', function() return nil end) == 0 and ({ D.load(st2, 'slrr_valo_city', make) })[1] ~= nil and st2.retry == false)
  -- a dealer with no parking spot stands on its door (T12 retest: the spots came back empty); no spot and no door = no place
  local doorApi = {
    list = function(kind) return kind == 'dealership' and { { id = 'belascoAuto' }, { id = 'lost' } } or {} end,
    spots = function() return {} end,
    door = function(f) return f.id == 'belascoAuto' and { x = 100, y = 200, z = 5, dx = 1, dy = 0 } or nil end,
  }
  local onDoor = D.fromFacilities(doorApi, 'west_coast_usa', tr)
  check('a dealer with no parking spot stands on its door, facing the way the door does', #onDoor == 1 and onDoor[1].id == 'stock_belascoauto' and onDoor[1].display[1] == 100
    and onDoor[1].displayDir[1] == 1 and #onDoor[1].displays == 1 and onDoor[1].stock.kind == 'dealer')
  doorApi.door = function() return { x = 1, y = 2, z = 0 } end
  check('a door whose facing is unknown faces north', D.fromFacilities(doorApi, 'west_coast_usa', tr)[1].displayDir[2] == 1)
  calls = 0
  check('Valo City asks the facilities for nothing and gets no places', #D.fromFacilities(api, 'slrr_valo_city', tr) == 0 and calls == 0 and #D.fromFacilities(nil, 'west_coast_usa', tr) == 0)
  check('only West Coast USA turns the stock facilities into places', progression.has('west_coast_usa', 'stockFacilities') and not progression.has('slrr_valo_city', 'stockFacilities'))

  -- T15 (a): which missions pay, by level and mission type (sl/core/activityrules)
  local AR = require('sl/core/activityrules')
  local W, V = 'west_coast_usa', 'slrr_valo_city'
  check('West Coast USA: a stock evade pays like a Valo City evade', AR.ruleFor(W, W .. '/evade/anyEvade').heat == -0.3 and AR.ruleFor(W, W .. '/evade/anyEvade').heatRep == 60)
  check('West Coast USA: parking, drift and time trials are rules', AR.ruleFor(W, W .. '/precisionParking/p1').firstOnly and AR.ruleFor(W, W .. '/drift/d1').fee == 50
    and AR.ruleFor(W, W .. '/timeTrial/t1').title == 'Street sprint')
  local tt = AR.ruleFor(W, W .. '/timeTrial/t1')
  check('a stock time trial pays its prize and rep once, not again and again (no money loop)', tt.prizeOnce and tt.firstOnly and tt.fee == 100 and tt.nightOnly)
  check('Valo City is unchanged: its sprints and evades by their slrr_ names only', AR.ruleFor(V, V .. '/timeTrial/slrr_sprint_x').prizeOnce == nil
    and AR.ruleFor(V, V .. '/evade/slrr_evade_x').heat == -0.3 and AR.ruleFor(V, V .. '/timeTrial/other') == nil and AR.ruleFor(V, V .. '/evade/other') == nil
    and AR.ruleFor(V, V .. '/timeTrial/slrr_rally_x').firstOnly)
  check('another level missions never pay, nor a missing id', AR.ruleFor(W, V .. '/evade/slrr_evade_x') == nil and AR.ruleFor(W, nil) == nil and AR.ruleFor(nil, 'a/evade/b') == nil)

  -- T15 (a): the tutorial on a map with no parts shops: step 2 is a courier run, steps already met pass at once
  local T = require('sl/tutorial')
  local old = { sl_jobs = _G.sl_jobs, sl_career = _G.sl_career, extensions = _G.extensions }
  local sent = {}
  _G.extensions = { hook = function() end }
  _G.sl_career = { sendText = function(_, text) sent[#sent + 1] = text end, addMoney = function(n, label) sent.money = (sent.money or 0) + n sent.label = label end, mapText = function(x) return x end,
    isActive = function() return false end }
  local leg = { id = 'x', name = 'a', x = 0, y = 0, z = 0 }
  local function jobs(withPart, withCourier)
    return { TYPES = { { kind = 'part', title = 'Part run', offer = function() return withPart and { legs = { leg, leg } } or nil end },
      { kind = 'courier', title = 'Courier', offer = function() return withCourier and { legs = { leg, leg } } or nil end } },
      summary = function() end }
  end
  local s1 = { day = 3, cars = { 1 }, jobs = { offers = {}, done = 0 }, racers = {}, known = {}, challenges = {}, stats = { races = 0 } }
  _G.sl_jobs = jobs(false, true)
  T.ensureFirstJob(s1)
  check('no part run possible: the tutorial puts a courier run first on the board', #s1.jobs.offers == 1 and s1.jobs.offers[1].kind == 'courier' and s1.jobs.offers[1].id == 'tutorial:job')
  T.ensureFirstJob(s1)
  check('...once', #s1.jobs.offers == 1)
  local s2 = { day = 3, cars = {}, jobs = { offers = { { kind = 'courier', id = 'courier:1' } }, done = 0 } }
  T.ensureFirstJob(s2)
  check('a courier already on the board is enough', #s2.jobs.offers == 1)
  _G.sl_jobs = jobs(true, true)
  local s3 = { day = 3, cars = {}, jobs = { offers = {}, done = 0 } }
  T.ensureFirstJob(s3)
  check('a part run is the first choice where there are shops', s3.jobs.offers[1].kind == 'part')
  _G.sl_jobs = jobs(false, false)
  local s4 = { day = 3, cars = {}, jobs = { offers = {}, done = 0 } }
  check('nothing possible: no error, nothing added', pcall(T.ensureFirstJob, s4) and #s4.jobs.offers == 0)
  -- a career that already has a car, jobs done, a part fitted and races run (the smoke test's): the tutorial still goes
  -- one step a call, each announced, and pays its bonus once at the end (T15: it once ran through all four at once)
  local s5 = { day = 3, cars = { 1 }, jobs = { offers = {}, done = 5, upgraded = true }, tutorial = { step = 1 }, racers = {}, known = {}, challenges = {}, stats = { races = 3 } }
  _G.sl_jobs = jobs(false, true)
  local steps = {}
  for _ = 1, 4 do T.advance(s5) steps[#steps + 1] = s5.tutorial.step or 'done' end
  check('four calls, four steps: 2, 3, 4, then done', steps[1] == 2 and steps[2] == 3 and steps[3] == 4 and steps[4] == 'done' and s5.tutorial.done == true)
  check('the courier run was put on the board for step 2 and the bonus paid once', s5.jobs.offers[1] and s5.jobs.offers[1].kind == 'courier' and sent.money == 500)
  T.advance(s5)
  check('...and not again', sent.money == 500)
  check('the bonus goes in the ledger as the welcome (what the smoke test looks for)', tostring(sent.label):find('Welcome to', 1, true) ~= nil)
  -- T15 (night run): from a known start extra looks (a frame hitch) never carry it past a step whose condition is not met,
  -- and the hour matters to none of them (only the street shops keep hours; the garage and the tutorial do not)
  local hoursLib = require('sl/core/hours')
  local midnight = 0.5
  check('the garage and the tutorial have no hours; the street shop does', hoursLib.isOpen('garage', midnight) and hoursLib.isOpen('tutorial', midnight) and not hoursLib.isOpen('shop', midnight))
  local s7 = { day = 3, cars = { 1 }, jobs = { offers = {}, done = 0 }, tutorial = { step = 1 }, racers = {}, known = {}, challenges = {}, stats = { races = 0 } }
  sent.money = nil
  for _ = 1, 3 do T.advance(s7) end
  check('extra looks: with a car and nothing else it waits on step 2 (the run)', s7.tutorial.step == 2)
  s7.jobs.done = 1
  for _ = 1, 3 do T.advance(s7) end
  check('...the run done: it waits on step 3 (a part), however often it looks', s7.tutorial.step == 3)
  s7.jobs.upgraded = true
  for _ = 1, 3 do T.advance(s7) end
  check('...the part fitted (at any hour): it waits on step 4 (the race)', s7.tutorial.step == 4 and sent.money == nil)
  s7.stats.races = 1
  T.advance(s7)
  check('...and the race run ends it, the bonus once', s7.tutorial.done == true and sent.money == 500)
  local s6 = { day = 3, cars = {}, jobs = { offers = {}, done = 0 }, tutorial = { step = 1 }, racers = {}, known = {}, challenges = {}, stats = { races = 0 } }
  T.advance(s6)
  check('no car: it waits on step 1', s6.tutorial.step == 1)
  _G.sl_jobs, _G.sl_career, _G.extensions = old.sl_jobs, old.sl_career, old.extensions

  -- T15 (c): a lot further than 60 m from its nearest lane is moved towards it, to 45 m
  local RS = require('sl/core/roadspot')
  local lane = { x = 100, y = 0, z = 10, dist = 100 }
  local to = RS.towards({ x = 0, y = 0, z = 0 }, lane, RS.LOT_REACH, RS.LOT_TARGET)
  check('a lot 100 m from its lane moves to 45 m from it, on the line', to and math.abs(to.x - 55) < 1e-9 and math.abs(to.y) < 1e-9 and math.abs(to.z - 5.5) < 1e-9)
  check('a lot 65 m from its lane (the smoke test) ends 45 m away', math.abs(RS.towards({ x = 0, y = 0, z = 0 }, { x = 65, y = 0, z = 0, dist = 65 }, 60, 45).x - 20) < 1e-9)
  check('a lot within 60 m stays; no lane at all stays', RS.towards({ x = 0, y = 0, z = 0 }, { x = 60, y = 0, z = 0, dist = 60 }, 60, 45) == nil and RS.towards({ x = 0, y = 0, z = 0 }, nil, 60, 45) == nil)
end
