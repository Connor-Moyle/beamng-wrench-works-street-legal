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
  -- T22: never police, service or race cars, and a short pool widens the dealer's own filter, narrowest key first
  local function raw(i, t) local r = { Value = i * 1000, Years = 1990 + i, ['Config Type'] = 'Factory', Population = 5000 } for k, v in pairs(t or {}) do r[k] = v end return r end
  local lots = {}
  for i = 1, 12 do lots[i] = { model = 'm' .. i, config = 'c' .. i, raw = raw(i) } end
  lots[13] = { model = 'cop', config = 'cop', raw = raw(13, { ['Config Type'] = 'Police' }) }
  lots[14] = { model = 'amb', config = 'amb', raw = raw(14, { ['Config Type'] = 'Service' }) }
  lots[15] = { model = 'race', config = 'race', raw = raw(15, { ['Config Type'] = 'Race' }) }
  lots[16] = { model = 'oneoff', config = 'oneoff', raw = raw(16, { Population = 1 }) }
  lots[17] = { model = 'agg', config = 'agg', raw = raw(17, { ['Config Type'] = 'Factory', aggregates = { ['Config Type'] = { Police = true } } }) }
  local function has(list, config) for _, c in ipairs(list) do if c.config == config then return true end end return false end
  local ge = function(c, f) for k, v in pairs(f.whiteList or {}) do if v.min and not (c.raw[k] and c.raw[k] >= v.min) then return false end end
    for k, v in pairs(f.blackList or {}) do if v.max and c.raw[k] and c.raw[k] <= v.max then return false end end return true end
  check('police, service, race, one-off and aggregate-police configs are not for sale', not D.forSale(lots[13]) and not D.forSale(lots[14]) and not D.forSale(lots[15])
    and not D.forSale(lots[16]) and not D.forSale(lots[17]) and D.forSale(lots[1]) and D.forSale({ model = 'x' }))
  local plain = D.pool(lots, { whiteList = { Value = { min = 6000 } } }, ge)
  check('a pool that passes its filter has none of them either', #plain == 7 and not has(plain, 'cop') and not has(plain, 'amb') and not has(plain, 'race') and not has(plain, 'oneoff') and not has(plain, 'agg'))
  local wide = D.pool(lots, { whiteList = { Value = { min = 11000 }, Years = { min = 1995 } } }, ge)
  check('too few: the narrowest key (Value, 2 cars) goes first, Years stays: 8 cars from 1995', #wide == 8 and has(wide, 'c5') and not has(wide, 'c4') and not has(wide, 'cop'))
  local all = D.pool(lots, { whiteList = { Value = { min = 99000 }, Years = { min = 2500 } } }, ge)
  check('nothing left to drop: every car for sale, still no police', #all == 12 and not has(all, 'cop') and not has(all, 'race') and not has(all, 'agg'))
  local black = D.pool(lots, { whiteList = { Value = { min = 99000 } }, blackList = { Value = { max = 4000 } } }, ge)
  check('the blackList is kept while widening', #black == 8 and not has(black, 'c4') and has(black, 'c5'))
  check('no filter: the cars for sale', #D.pool(lots, nil, ge) == 12 and #D.pool(lots, { whiteList = { Value = { min = 1 } } }, nil) == 12)
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
  -- T37: more cars on a lot, in the map's painted parking bays around it
  local RSP = require('sl/core/roadspot')
  local own = { { x = 0, y = 0, z = 5, dx = 0, dy = 1 } }
  local function bay(x, y, o) o = o or {} return { x = x, y = y, z = o.z or 5, dx = o.dx or 0, dy = o.dy or 1, occupied = o.occupied } end
  local row = { bay(4, 0), bay(8, 0), bay(12, 0), bay(16, 0), bay(20, 0), bay(24, 0), bay(28, 0) }
  local w = D.withBays(own, row, {})
  check('a lot gets its own spot first, then the nearest bays, six in all', #w == 6 and w[1] == own[1] and w[2].x == 4 and w[3].x == 8 and w[6].x == 20)
  local far = D.withBays(own, { bay(4, 0), bay(8, 0), bay(100, 0), bay(40, 0) }, {})
  check('a bay beyond 38 m is not used', #far == 3 and far[3].x == 8)
  local mixed = D.withBays(own, { bay(4, 0, { z = 7 }), bay(8, 0), bay(12, 0, { occupied = true }), bay(16, 0), bay(20, 0, { z = 4.2 }) }, {})
  check('a bay more than 1 m up or down, or taken by a parked car, is skipped (0.8 m is the same level)', #mixed == 4 and mixed[2].x == 8 and mixed[3].x == 16 and mixed[4].x == 20)
  check('a bay carries its own position and facing (the car stands centred between the lines)', w[2].dx == 0 and w[2].dy == 1 and D.withBays(own, { bay(4, 0, { dx = 1, dy = 0 }), bay(8, 0), bay(12, 0) }, {})[2].dx == 1)
  -- a road along y = 10 (7 m wide) between the lot and the bays above it; the bays at y = 3 are on the lot's side
  local road = { { x1 = -50, y1 = 10, x2 = 50, y2 = 10, half = 3.5 } }
  local side = D.withBays(own, { bay(3, 3), bay(-3, 3), bay(6, 3), bay(0, 14), bay(5, 14), bay(0, 10) }, road)
  check('a bay across a road from the lot, or on the road, is not used', #side == 4 and side[2].y == 3 and side[3].y == 3 and side[4].y == 3)
  check('a lot with fewer than three spots in all keeps its own', #D.withBays(own, { bay(4, 0) }, {}) == 1 and D.withBays(own, { bay(4, 0) }, {})[1] == own[1] and #D.withBays(own, {}, {}) == 1)
  check('a bay on top of the lot spot is not used twice', #D.withBays(own, { bay(0.5, 0.5), bay(4, 0), bay(8, 0) }, {}) == 3)
  check('a door spot (made up) and nothing at all stay as they are', #D.withBays({ { x = 0, y = 0, z = 5, dx = 0, dy = 1, synthetic = true } }, row, {}) == 1 and #D.withBays({}, row, {}) == 0 and #D.withBays(own, nil, {}) == 1)
  check('the road geometry: crossing segments are 0 apart, parallel ones the gap, a point segment the point distance', RSP.segDist(0, 0, 10, 0, 5, -5, 5, 5) == 0
    and math.abs(RSP.segDist(0, 0, 10, 0, 0, 3, 10, 3) - 3) < 1e-9 and math.abs(RSP.segDist(2, 2, 2, 2, 0, 0, 10, 0) - 2) < 1e-9)
  local rn = { a = { pos = { x = 0, y = 0 }, radius = 3, links = { b = { drivability = 1 }, c = { drivability = 1, type = 'private' } } },
    b = { pos = { x = 40, y = 0 }, radius = 4, links = { a = { drivability = 1 } } }, c = { pos = { x = 0, y = 30 }, radius = 3, links = { a = { type = 'private' } } },
    far = { pos = { x = 900, y = 900 }, radius = 3, links = { far2 = { drivability = 1 } } }, far2 = { pos = { x = 940, y = 900 }, radius = 3, links = { far = { drivability = 1 } } } }
  local segs = RSP.roadSegments(rn, 10, 5, 60)
  check('road segments: the public link near the point (half = the narrower end), not the private one, not the far one', #segs == 1 and segs[1].half == 3 and segs[1].x2 == 40)
  local dealerBays = D.dealer({ id = 'jeffersonmotors', filter = newF }, own, tr, function() return row, {} end)
  check('a stock dealer place lists the bays as its display spots, its own spot first', #dealerBays.displays == 6 and dealerBays.display[1] == 0 and dealerBays.displays[2].pos[1] == 4)
  check('...and only its own spot without a bay lookup (Valo City never gets any)', #D.dealer({ id = 'jeffersonmotors', filter = newF }, own, tr).displays == 1)
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
    and AR.ruleFor(W, W .. '/timeTrial/t1').title == 'Time trial')
  local tt = AR.ruleFor(W, W .. '/timeTrial/t1')
  check('a stock time trial pays its prize and rep once, not again and again (no money loop)', tt.prizeOnce and tt.firstOnly and tt.fee == 100 and tt.kind == 'timeTrial' and not tt.nightOnly)
  check('the drag strips and circuits of a stock map are day events with prize money', AR.ruleFor(W, W .. '/dragStripRace/a').kind == 'drag' and AR.ruleFor(W, W .. '/dragStripAPM/a').prize > 0
    and AR.ruleFor(W, W .. '/aiRace/a').kind == 'circuit' and AR.ruleFor(V, V .. '/aiRace/a') == nil)
  local roc = AR.ruleFor(W, W .. '/aiRace/001-circuit')
  check('the Race of Champions is the first circuit of the race track: a day event with the entry fee and the big prize, other circuits are plain', roc.roc and roc.kind == 'circuit' and roc.fee == 50000 and roc.prize == 250000
    and AR.ruleFor(W, W .. '/aiRace/002-highway').roc == nil and AR.ruleFor(V, V .. '/aiRace/001-circuit') == nil)
  check('ROC entry: closed below garage 3 or 6000 reputation, open with both; only the gold star wins it', AR.rocGate({ garageLevel = 2, rep = 9000 }) ~= nil and AR.rocGate({ garageLevel = 3, rep = 5000 }) ~= nil
    and AR.rocGate({ garageLevel = 3, rep = 6000 }) == nil and AR.rocGate({}) ~= nil and AR.rocWon({ finishGold = true, finishSilver = true }) and not AR.rocWon({ finishSilver = true }) and not AR.rocWon(nil))
  check('at night the day events are closed (no marker), by day and the street things not', AR.closed(W, W .. '/timeTrial/t1', 'night') and AR.closed(W, W .. '/dragStripRace/a', 'night')
    and not AR.closed(W, W .. '/timeTrial/t1', 'day') and not AR.closed(W, W .. '/evade/e', 'night') and not AR.closed(W, W .. '/drift/d', 'night') and not AR.closed(W, 'x/timeTrial/t1', 'night'))
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

  -- the junkyard and the private sellers offer no police: the lot pool is the cars for sale
  check('forSale keeps a normal car and drops police, race and one-off configs', D.forSale({ raw = { ['Config Type'] = 'Factory', Population = 5000 } }) and not D.forSale({ raw = { ['Config Type'] = 'Police' } })
    and not D.forSale({ raw = { ['Config Type'] = 'Race' } }))

  -- T29: the changes a car for sale gets are the ones the game's slot rules allow (sl/core/cars)
  local C = require('sl/core/cars')
  check('partFits: a list of types, allowTypes, denyTypes, a v1 type, no definition', C.partFits('rim', { allowTypes = { 'rim', 'wheel' } }) and not C.partFits('tire', { allowTypes = { 'rim' } })
    and C.partFits({ 'x', 'rim' }, { allowTypes = { 'rim' } }) and not C.partFits({ 'rim', 'bad' }, { allowTypes = { 'rim', 'bad' }, denyTypes = { 'bad' } })
    and C.partFits('rim', { type = 'rim' }) and not C.partFits('tire', { type = 'rim' }) and C.partFits('anything', nil))
  local function tree()
    return { chosenPartName = 'main', children = {
      intake = { id = 'intake', path = '/intake/', chosenPartName = 'intake_a', suitablePartNames = { 'intake_a', 'intake_b' }, children = {} },
      fuel = { id = 'fuel', path = '/fuel/', chosenPartName = 'tank', suitablePartNames = { 'tank' }, children = {} },
      exhaust = { id = 'exhaust', path = '/exhaust/', chosenPartName = 'exh', suitablePartNames = { 'exh' }, children = {
        tip = { id = 'tip', path = '/exhaust/tip/', chosenPartName = 'tip_a', suitablePartNames = { 'tip_a' }, children = {} } } },
      rims_f = { id = 'rims_f', path = '/rims_f/', chosenPartName = 'rim_a', suitablePartNames = { 'rim_a', 'rim_b', 'rim_tyre' }, children = {} },
    } }
  end
  local classifyKinds = { intake = { 'engine', 'intake' }, fuel = { 'engine', 'fuel' }, exhaust = { 'engine', 'exhaust' }, rims_f = { 'running', 'rims_f' } }
  local function classifyStub(id) local k = classifyKinds[id] if k then return k[1], k[2] end return 'body', 'misc' end
  local slots = { intake = { allowTypes = { 'intake' } }, fuel = { coreSlot = true, allowTypes = { 'tank' } }, exhaust = { allowTypes = { 'exh' } },
    tip = { coreSlot = true, allowTypes = { 'tip' } }, rims_f = { allowTypes = { 'rim' } } }
  local slotOf = function(node) return slots[node.id] end
  local slotTypes = { rim_a = 'rim', rim_b = 'rim', rim_tyre = 'tire' }
  local function tweak(faults, mods, seed, guarded)
    local tr = tree()
    local r = C.tweakTree(tr, { rng = rngLib.new(rngLib.hash('t' .. tostring(seed or 1))), classify = classifyStub, valueOf = function(n) return n == 'rim_tyre' and 100 or 1 end,
      faults = faults, mods = mods, slotOf = guarded and slotOf or nil, partSlotType = guarded and function(n) return slotTypes[n] end or nil })
    return r, tr
  end
  local r1, t1 = tweak({ 'engine' }, 0, 1, true)
  check('a fault takes off a part from an ordinary slot', #r1.removed == 1 and r1.removed[1] == '/intake/intake_a' and t1.children.intake.chosenPartName == '' and #r1.refused == 0)
  local r2, t2 = tweak({ 'battery' }, 0, 1, true)
  check('...but never from a core slot', #r2.removed == 0 and #r2.refused == 1 and r2.refused[1].why == 'core slot' and t2.children.fuel.chosenPartName == 'tank')
  local r3, t3 = tweak({ 'exhaust' }, 0, 1, true)
  check('...nor from a part with a core slot below it', #r3.removed == 0 and r3.refused[1].why == 'core slot below' and t3.children.exhaust.chosenPartName == 'exh' and t3.children.exhaust.children.tip.chosenPartName == 'tip_a')
  local r4 = tweak({ 'engine', 'battery', 'exhaust' }, 0, 1, false)
  check('without the slot lookups the old rules apply: all three come off', #r4.removed == 3 and #r4.refused == 0)
  local wrong, swappedOk = 0, 0
  for seed = 1, 30 do
    local r = tweak({}, 1, seed, true)
    for _, x in ipairs(r.swapped) do if x.to == 'rim_tyre' then wrong = wrong + 1 elseif x.to == 'rim_b' then swappedOk = swappedOk + 1 end end
  end
  check('a swap goes only to a part the slot takes (the dearest, but a tyre in a rim slot never)', wrong == 0 and swappedOk > 0)
  local unguardedWrong = 0
  for seed = 1, 30 do for _, x in ipairs(tweak({}, 1, seed, false).swapped) do if x.to == 'rim_tyre' then unguardedWrong = unguardedWrong + 1 end end end
  check('(the old rule did pick it: that is what the guard stops)', unguardedWrong > 0)
  local r5 = tweak({}, 1, 1, true)
  local refusedWrong = false
  for _, x in ipairs(r5.refused) do if x.path:find('rim_tyre', 1, true) and x.why == 'does not fit the slot' then refusedWrong = true end end
  check('a part refused for its slot is named', refusedWrong)

  -- T33: every lot of the career has a marker, a big-map entry and a prompt (sl/core/pois)
  local PO = require('sl/core/pois')
  local places = {
    dealer = { id = 'dealer', kind = 'dealer', name = 'Jefferson Motors', at = { x = 10, y = 20, z = 1 }, stockId = 'jeffersonmotors' },
    stock_belascoauto = { id = 'stock_belascoauto', kind = 'dealer', name = 'Belasco Auto', at = { x = 30, y = 40, z = 2 }, stockId = 'belascoAuto' },
    junkyard = { id = 'junkyard', kind = 'junkyard', name = 'Quarry Road Wrecks', at = { x = 50, y = 60, z = 3 } },
    scrapyard = { id = 'scrapyard', kind = 'scrapyard', name = 'Sealbrik', at = { x = 70, y = 80, z = 4 } },
    hospital = { id = 'hospital', kind = 'hospital', name = 'Hospital', at = { x = 1, y = 1, z = 1 } },
    meet_docks = { id = 'meet_docks', kind = 'meet', name = 'Dockyards', at = { x = 2, y = 2, z = 2 } },
    belascoCityGarage = { id = 'belascoCityGarage', kind = 'garage', name = 'Belasco City Garage', at = { x = 3, y = 3, z = 3 } },
    nowhere = { id = 'nowhere', kind = 'dealer', name = 'No position' },
  }
  local recs = PO.records(places)
  local byPlace = {}
  for _, r in ipairs(recs) do byPlace[r.placeId] = r end
  check('every dealer, used lot and scrap yard with a position has a marker; the other places have none', #recs == 4 and byPlace.dealer and byPlace.stock_belascoauto and byPlace.junkyard and byPlace.scrapyard
    and not byPlace.hospital and not byPlace.meet_docks and not byPlace.belascoCityGarage and not byPlace.nowhere)
  check('a dealer is a dealership in the big map with the dealer icon; the lots are "other"', byPlace.dealer.type == 'dealership' and byPlace.dealer.cardIcon == 'carDealer'
    and byPlace.junkyard.type == 'other' and byPlace.scrapyard.type == 'other')
  check('the record carries the place, its name, its position and the stock dealership it is', byPlace.dealer.placeId == 'dealer' and byPlace.dealer.name == 'Jefferson Motors'
    and byPlace.dealer.pos[1] == 10 and byPlace.dealer.pos[3] == 1 and byPlace.dealer.stockId == 'jeffersonmotors' and byPlace.junkyard.stockId == nil)
  local seen, unique = {}, true
  for _, r in ipairs(recs) do if seen[r.poiId] then unique = false end seen[r.poiId] = true end
  check('POI ids are unique, stable and sorted by place', unique and recs[1].placeId == 'dealer' and recs[1].poiId == 'sl_place_dealer' and recs[4].placeId == 'stock_belascoauto')
  check('no places, no markers', #PO.records(nil) == 0 and #PO.records({}) == 0)
  local D2 = require('sl/core/stockdealers')
  check('a stock dealer place remembers which stock dealership it is, for its marker', D2.dealer({ id = 'jeffersonmotors', filter = {} }, { { x = 1, y = 2, z = 3, dx = 0, dy = 1 } }, nil).stockId == 'jeffersonmotors')

  -- T39: how a part ad reads (sl/core/partinfo)
  local PI = require('sl/core/partinfo')
  check('a jbeam display name is kept as it is', PI.displayName('Sport exhaust', 'covet_exhaust_sport', 'covet') == 'Sport exhaust')
  check('a name that is a table never shows as one: its text, else the id in words', PI.displayName({ txt = 'Sport exhaust' }, 'covet_exhaust_sport', 'covet') == 'Sport exhaust'
    and PI.displayName({}, 'covet_exhaust_sport', 'covet') == 'Exhaust sport' and PI.displayName({ { } }, { }, 'covet') == 'Part' and PI.text({ 'a' }) == 'a' and PI.text({}) == nil)
  check('an internal id as the name becomes words (the model prefix dropped)', PI.displayName('covet_exhaust_sport_2', 'covet_exhaust_sport_2', 'covet') == 'Exhaust sport 2'
    and PI.displayName(nil, 'etk800_body/fender_L', 'etk800') == 'Body fender l' and PI.displayName('', 'x', 'y') == 'X' and PI.displayName(nil, nil, nil) == 'Part')
  check('a part picture is used only when the manifest lists it, under its safe file name', PI.picture('covet_exhaust_sport', { covet_exhaust_sport = true }) == '/art/street_legal/parts/covet_exhaust_sport.png'
    and PI.picture('etk800_body/fender_L', { etk800_body_fender_L = true }) == '/art/street_legal/parts/etk800_body_fender_L.png' and PI.picture('x', {}) == nil and PI.picture('x', nil) == nil
    and PI.picture('covet_mirror_R', { covet_mirror_R = 'covet_mirror_L' }) == '/art/street_legal/parts/covet_mirror_L.png')
  local cat = {
    classify = function(slotId) if slotId == 'exhaust' then return 'engine', 'exhaust' end return 'body', 'misc' end,
    sections = { { id = 'engine', title = 'ENGINE', subs = { { id = 'exhaust', title = 'EXHAUST SYSTEMS' } } }, { id = 'body', title = 'BODY', subs = { { id = 'misc', title = 'MISC BODY' } } } },
  }
  local d = PI.describe({ part = 'covet_exhaust_sport', name = 'Sport exhaust', slotId = 'exhaust', model = 'covet' }, cat)
  check('describe: name, category, its title and the catalog chapter', d.name == 'Sport exhaust' and d.category == 'engine' and d.categoryTitle == 'Engine' and d.chapter == 'Exhaust systems')
  local g = PI.describe({ part = 'p', name = 'Rear bumper', slotId = 'etk800_bumper_R', model = 'etk800' }, nil)
  check('without the catalog the category is guessed from the slot name, no chapter', g.category == 'body' and g.categoryTitle == 'Body' and g.chapter == nil)
  check('guesses: engine, running gear, interior, paint; unknown is just a part', PI.describe({ slotId = 'turbo_main' }, nil).category == 'engine' and PI.describe({ slotId = 'wheel_F' }, nil).category == 'running'
    and PI.describe({ slotId = 'seat_fl' }, nil).category == 'interior' and PI.describe({ slotId = 'paint_design' }, nil).category == 'paint'
    and PI.describe({ slotId = 'zzz' }, nil).category == 'part' and PI.describe({ slotId = 'zzz' }, nil).categoryTitle == 'Part')
  check('a catalog that errors or has no section still gives a category from the slot', PI.describe({ slotId = 'exhaust_x' }, { classify = function() error('x') end }).category == 'engine'
    and PI.describe({ slotId = 'exhaust_x' }, { classify = function() return 'nonsense', 'x' end }).category == 'engine')

  -- T37b: the bays source loads late (nil, then there): the places are built again and the lot gets its bays
  local late, calls2 = false, 0
  local lateApi = {
    list = function(kind) return kind == 'dealership' and { { id = 'jeffersonmotors', filter = newF } } or {} end,
    spots = function() return { { x = 0, y = 0, z = 5, dx = 0, dy = 1 } } end,
    door = function() return nil end,
    bays = function() calls2 = calls2 + 1 if not late then return nil, nil end return { bay(4, 0), bay(8, 0), bay(12, 0) }, {} end,
  }
  local lst, lstate = nil, {}
  lst = D.load(lstate, 'west_coast_usa', function() return lateApi, tr end)
  check('the bay source not there yet: the dealer keeps its own spot and the places are asked for again', #lst == 1 and #lst[1].displays == 1 and lstate.retry == true)
  late = true
  lst = D.load(lstate, 'west_coast_usa', function() return lateApi, tr end)
  check('...it is there the second time: the lot has its bays and the asking stops', #lst[1].displays == 4 and lstate.retry == false and calls2 == 2)
  local fresh = {}
  for _ = 1, D.MAX_TRIES do late = false D.load(fresh, 'west_coast_usa', function() return lateApi, tr end) end
  check('a source that never comes is asked for MAX_TRIES times, then left', fresh.retry == false and fresh.tries == D.MAX_TRIES)

  -- T37b: the lot camera stands on the side with room and never inside a wall (sl/core/lotcam)
  local LC = require('sl/core/lotcam')
  local car, facing = { x = 100, y = 100, z = 10 }, { x = 0, y = 1 }
  local clear = function() return nil end
  local yaw0, f0 = LC.choose(car, facing, LC.PITCH, LC.DIST, clear)
  check('a clear lot: the first rear quarter (145 degrees)', math.abs(yaw0 - math.rad(145)) < 1e-9 and f0 == 1)
  local fdist, fpitch = LC.frame(5.5)
  local eye0 = LC.eyeAt(car, facing, yaw0, fpitch, fdist)
  check('the eye is behind the car and to its side, EYE_UP above its centre (a low hero shot), 6.5 to 10 m out', eye0.y < car.y and math.abs(eye0.x - car.x) > 2.5 and math.abs(eye0.z - car.z - LC.EYE_UP) < 0.01
    and fdist >= 6.5 and fdist <= 10 and math.abs(math.sqrt((eye0.x - car.x) ^ 2 + (eye0.y - car.y) ^ 2) - fdist * math.cos(fpitch)) < 1e-6)
  check('the eye is raised 2 to 20 degrees above the car for an ordinary car (low hero shot)', math.deg(fpitch) > 2 and math.deg(fpitch) < 20)
  local small, _ = LC.frame(2.5)
  local big, _ = LC.frame(30)
  check('the distance follows the car size: never under 6.5 m, never over 10 m, more for a bigger car', small == 6.5 and big == 10 and LC.frame(8) > LC.frame(5))
  -- the screen: the camera looks at a point DROP * dist below the car centre, so the car stands above the middle of the screen
  local atan = math.atan2 or math.atan
  local dropM = LC.DROP * fdist
  local lookAngle = atan(eye0.z - (car.z - dropM), math.sqrt((eye0.x - car.x) ^ 2 + (eye0.y - car.y) ^ 2))
  local carAngle = atan(eye0.z - car.z, math.sqrt((eye0.x - car.x) ^ 2 + (eye0.y - car.y) ^ 2))
  local above = math.deg(lookAngle - carAngle)
  check('the car centre is 8 to 18 degrees above the middle of the picture (clear of the info card over the bottom 40 percent)', above > 8 and above < 18)
  -- a building along the car's back (y < 97): everything behind is blocked at the wall; the sides are clear
  local wallBehind = function(a, b) if b.y < 97 then return math.abs((97 - a.y) / (b.y - a.y)) * math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2) end end
  local yaw1, f1 = LC.choose(car, facing, LC.PITCH, LC.DIST, wallBehind)
  local eye1 = LC.eyeAt(car, facing, yaw1, LC.PITCH, LC.DIST)
  check('a wall behind the car: the camera takes the first yaw whose eye is not behind the wall (the sides)', f1 == 1 and eye1.y >= 97 and math.abs(math.deg(yaw1)) <= 90)
  local pulled, frac = LC.pull(car, { x = 100, y = 90, z = 11.75 }, wallBehind)
  check('an eye behind a wall is pulled in front of it, with room kept', frac < 1 and pulled.y > 97 and pulled.y < car.y)
  local boxed = function(a, b) return 3 end                    -- everything 3 m away is a wall
  local yaw2, f2 = LC.choose(car, facing, LC.PITCH, LC.DIST, boxed)
  check('boxed in on every side: the clearest (all equal: the first), at least 1.5 m out', f2 < 1 and math.abs(yaw2 - math.rad(145)) < 1e-9)
  local pulledBox = LC.pull(car, LC.eyeAt(car, facing, yaw2, LC.PITCH, LC.DIST), boxed)
  check('...and the eye stays at least 1.5 m from the car', math.sqrt((pulledBox.x - car.x) ^ 2 + (pulledBox.y - car.y) ^ 2 + (pulledBox.z - car.z - 0.8) ^ 2) >= 1.5 - 1e-9)
  check('a car facing another way gets the quarter relative to it', math.abs(LC.eyeAt(car, { x = 1, y = 0 }, math.rad(145), LC.PITCH, LC.DIST).x - car.x) > 4)

  -- T29: a spare wheel (any model) is never taken off or swapped, nor the part it hangs from
  local function spareTree()
    return { chosenPartName = 'main', children = {
      rims_f = { id = 'rims_f', path = '/rims_f/', chosenPartName = 'rim_a', suitablePartNames = { 'rim_a', 'rim_b' }, children = {} },
      body = { id = 'body', path = '/body/', chosenPartName = 'midtruck_body', suitablePartNames = { 'midtruck_body' }, children = {
        reardoor = { id = 'midtruck_reardoor', path = '/body/midtruck_reardoor/', chosenPartName = 'midtruck_reardoor', suitablePartNames = { 'midtruck_reardoor', 'midtruck_reardoor_b' }, children = {
          spare = { id = 'midtruck_sparewheel', path = '/body/midtruck_reardoor/midtruck_sparewheel/', chosenPartName = 'midtruck_sparewheel_steel',
            suitablePartNames = { 'midtruck_sparewheel_steel', 'midtruck_sparewheel_steel_alt', 'midtruck_sparewheel_beadlock' }, children = {} } } } } },
    } }
  end
  local spareKinds = { rims_f = { 'running', 'rims_f' }, midtruck_sparewheel = { 'running', 'rims_f' }, midtruck_reardoor = { 'body', 'doors' } }
  local function spareClassify(id) local k = spareKinds[id] if k then return k[1], k[2] end return 'body', 'misc' end
  local touched = 0
  for seed = 1, 60 do
    local tr = spareTree()
    local r = C.tweakTree(tr, { rng = rngLib.new(rngLib.hash('sp' .. seed)), classify = spareClassify, valueOf = function() return 1 end, faults = {}, mods = 3 })
    local spare = tr.children.body.children.reardoor.children.spare
    if spare.chosenPartName ~= 'midtruck_sparewheel_steel' or tr.children.body.children.reardoor.chosenPartName ~= 'midtruck_reardoor' then touched = touched + 1 end
    for _, x in ipairs(r.swapped) do if tostring(x.path):find('spare', 1, true) or tostring(x.path):find('reardoor', 1, true) then touched = touched + 1 end end
  end
  check('a spare wheel slot (and the door it hangs on) is never swapped, over 60 random cars with 3 modifications each', touched == 0)
  local trF = spareTree()
  local rF = C.tweakTree(trF, { rng = rngLib.new(1), classify = function(id) if id == 'midtruck_sparewheel' then return 'engine', 'intake' end return 'body', 'misc' end, valueOf = function() return 1 end, faults = { 'engine' }, mods = 0 })
  check('...nor taken off by a fault, and the refusal is named', #rF.removed == 0 and #rF.refused == 1 and rF.refused[1].why:find('spare', 1, true) ~= nil and trF.children.body.children.reardoor.children.spare.chosenPartName == 'midtruck_sparewheel_steel')
  local otherSwaps = 0
  for seed = 1, 60 do
    local tr = spareTree()
    local r = C.tweakTree(tr, { rng = rngLib.new(rngLib.hash('sp' .. seed)), classify = spareClassify, valueOf = function() return 1 end, faults = {}, mods = 3, refuse = { 'nothing' } })
    for _, x in ipairs(r.swapped) do if tostring(x.path):find('spare', 1, true) then otherSwaps = otherSwaps + 1 end end
  end
  check('the list is the caller own (the proof the rule is what protects it): with another list the spare wheel does get swapped', otherSwaps > 0)
  check('the default list names the spare wheel in its spellings', table.concat(C.REFUSE, ' '):find('sparewheel', 1, true) ~= nil and table.concat(C.REFUSE, ' '):find('spare_wheel', 1, true) ~= nil)

  -- T37c: the camera looks DOWN at the car, not up into the sky
  local aim = { x = car.x, y = car.y, z = car.z - LC.DROP * fdist }
  local lookDz = aim.z - eye0.z
  check('the eye is above the car and the point it looks at is below the eye: the look direction points down', eye0.z > car.z and aim.z < car.z and lookDz < 0)
  local yawD, pitchD = LC.angles(aim.x - eye0.x, aim.y - eye0.y, lookDz)
  check('...so the camera pitch is positive (scriptedFree: positive = down), 15 to 25 degrees for the standard framing', pitchD > 15 and pitchD < 25)
  local fx, fy, fz = math.sin(math.rad(yawD)) * math.cos(math.rad(pitchD)), math.cos(math.rad(yawD)) * math.cos(math.rad(pitchD)), -math.sin(math.rad(pitchD))
  local dl = math.sqrt((aim.x - eye0.x) ^ 2 + (aim.y - eye0.y) ^ 2 + lookDz ^ 2)
  check('the camera forward from those angles (scriptedFree own formula) is the direction to the aim point, z negative', math.abs(fx - (aim.x - eye0.x) / dl) < 1e-9 and math.abs(fy - (aim.y - eye0.y) / dl) < 1e-9 and math.abs(fz - lookDz / dl) < 1e-9 and fz < 0)
  local y1, p1 = LC.angles(0, 1, 0)
  local y2, p2 = LC.angles(1, 0, 0)
  local y3, p3 = LC.angles(0, -1, -1)
  local _, p4 = LC.angles(0, 1, 1)
  check('angles: +Y is yaw 0, +X is yaw 90, a descending look has positive pitch, a rising one negative, a zero vector is 0', math.abs(y1) < 1e-9 and math.abs(p1) < 1e-9 and math.abs(y2 - 90) < 1e-9
    and math.abs(math.abs(y3) - 180) < 1e-9 and math.abs(p3 - 45) < 1e-9 and math.abs(p4 + 45) < 1e-9 and select(1, LC.angles(0, 0, 0)) == 0)

  -- T29: panels a car is never dented on (carsLib.REFUSE_DENTS)
  local function dentTree()
    return { chosenPartName = 'main', children = {
      hood = { id = 'hood', path = '/hood/', chosenPartName = 'midtruck_hood', children = {} },
      bumper = { id = 'bumper_F', path = '/bumper_F/', chosenPartName = 'midtruck_bumper_F', children = {} },
      cargo = { id = 'cargo', path = '/cargo/', chosenPartName = 'midtruck_cargobox', children = { tail = { id = 'tailgate', path = '/cargo/tailgate/', chosenPartName = 'midtruck_tailgate', children = {} } } },
      roof = { id = 'roof', path = '/roof/', chosenPartName = 'midtruck_roof', children = {} },
    } }
  end
  local dentKinds = { hood = 'hoods', bumper_F = 'bumpers_f', cargo = 'trunk', roof = 'roof', tailgate = 'trunk' }
  local function dentClassify(id) return 'body', dentKinds[id] or 'misc' end
  local function dentedPaths(refuse, seed)
    local out = {}
    for _, d in ipairs(C.dents(dentTree(), dentClassify, rngLib.new(seed or 5), 1, refuse)) do out[d.partPath] = true end
    return out
  end
  local all = dentedPaths({})
  check('without a refusal every panel of the body takes a dent at full damage', all['/hood/midtruck_hood'] and all['/bumper_F/midtruck_bumper_F'] and all['/cargo/midtruck_cargobox'] and all['/cargo/tailgate/midtruck_tailgate'] and all['/roof/midtruck_roof'])
  check('the default list is empty (the panel is found by the probe)', #C.REFUSE_DENTS == 0)
  local some = dentedPaths({ 'cargo' })
  check('a refused word keeps the panel, and a panel with such a part below it, from every dent', not some['/cargo/midtruck_cargobox'] and not some['/cargo/tailgate/midtruck_tailgate'] and some['/hood/midtruck_hood'] and some['/roof/midtruck_roof'])
  local byChild = dentedPaths({ 'tailgate' })
  check('...the parent of a refused part too (the box the tailgate hangs on)', not byChild['/cargo/midtruck_cargobox'] and not byChild['/cargo/tailgate/midtruck_tailgate'] and byChild['/hood/midtruck_hood'])
  local lcase = dentedPaths({ 'hood' })
  check('matching is on the slot path, id and part name, lower case', not lcase['/hood/midtruck_hood'] and lcase['/roof/midtruck_roof'])

  -- T29: no lot lists an excluded model (the midtruck): one pool rule for the lots, the stock dealers, the laptop dealers and the private ads
  local pool0 = {}
  for i = 1, 8 do pool0[#pool0 + 1] = { model = 'covet', config = 'covet' .. i, value = 1000 * i, raw = { ['Config Type'] = 'Factory', Population = 5000, Value = 1000 * i } } end
  for i = 1, 6 do pool0[#pool0 + 1] = { model = 'midtruck', config = 'midtruck' .. i, value = 9000 + i, raw = { ['Config Type'] = 'Factory', Population = 5000, Value = 9000 + i } } end
  pool0[#pool0 + 1] = { model = 'sunburst2', config = 'cop', value = 7000, raw = { ['Config Type'] = 'Police', Population = 5000 } }
  local lotPool = D.lotPool(pool0, { midtruck = true })
  local midtrucks, cops = 0, 0
  for _, c in ipairs(lotPool) do if c.model == 'midtruck' then midtrucks = midtrucks + 1 end if c.config == 'cop' then cops = cops + 1 end end
  check('the lot pool has the covets only: no midtruck, no police car', #lotPool == 8 and midtrucks == 0 and cops == 0)
  check('without an exclusion list only the for-sale rule applies', #D.lotPool(pool0, nil) == 14 and #D.lotPool(pool0, {}) == 14 and #D.lotPool(nil, { midtruck = true }) == 0)
  local viaDealer = D.pool(lotPool, { whiteList = { Value = { min = 1 } } }, function(c, f) return c.raw.Value >= f.whiteList.Value.min end)
  local viaDealerTrucks = 0
  for _, c in ipairs(viaDealer) do if c.model == 'midtruck' then viaDealerTrucks = viaDealerTrucks + 1 end end
  check('a stock dealer filter on that pool, however wide it is widened, has no midtruck', viaDealerTrucks == 0 and #viaDealer == 8
    and #D.pool(lotPool, { whiteList = { Value = { min = 99999 } } }, function(c, f) return c.raw.Value >= f.whiteList.Value.min end) == 8)
  local offers = require('sl/core/market').offers(lotPool, 'used', 'seed', 4, 20)
  local offerTrucks = 0
  for _, o in ipairs(offers) do if o.model == 'midtruck' then offerTrucks = offerTrucks + 1 end end
  check('the offers made from the pool (used, private ad, laptop dealer: all through the same pool) have no midtruck', #offers > 0 and offerTrucks == 0)

  -- (the pool tests are in ai_pool_test.lua: this function has no local variables left)
  assert(loadfile(debug.getinfo(1, 'S').source:match('^@(.*[/' .. string.char(92) .. '])') .. 'ai_pool_test.lua'))()(check, rngLib)
end
