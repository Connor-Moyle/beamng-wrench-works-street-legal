-- Wrench Works: Street Legal: the used parts market (extension name: sl_classifieds; Design 4, X12). The
-- Revline app's listings: parts for the cars you own (and a few others) from private sellers round town,
-- refreshed through the day. Haggle, then pick it up at the seller's kerb (a job with a marker; a deposit
-- up front) or pay for delivery to your garage shelf. Rules in sl/core/listings; parts reach Wrench Works'
-- shelf through slrr_garage.addShelfPart, valued at what was paid.

local carreport = require('sl/core/carreport')
local usedcar = require('sl/core/usedcar')
local barnRules = require('sl/core/barn')
local M = {}

local strings = require('sl/core/strings')

local L = require('sl/core/listings')
local rngLib = require('sl/core/rng')
local stateLib = require('sl/core/state')
local jbeamIO = require('jbeam/io')         -- (not a global on the game-engine side)
local market = require('sl/core/market')
local builder = require('sl/carBuilder')
local dealersLib = require('sl/core/dealers')
local carInfo = require('sl/carInfo')
local partinfo = require('sl/core/partinfo')

local REFRESH_HOURS = 6        -- new listings every few in-game hours
local APP_LISTINGS = 12
local CAR_ADS = 3                           -- of Revline's ads, private cars (sl_lot's used-lot offers)
local PAPER_LISTINGS, PRINT_ONLY = 3, 0.4    -- Valo Classifieds: ads up at a time (each lasts a day); some only in print
local AUCTIONS = 6                          -- Swap & Bid lots open at a time
local PAPER_REACH = 30                      -- metres from a gas station to buy a copy
local swapmeet = require('sl/core/swapmeet')
local MEET_STALLS, MEET_REACH = 6, 40   -- the weekend swap meet: at the Tuning shop lot on Valo City, the lot with most room on a map without one (#44)
local MINE_MAX = 6                          -- your own listings at a time
local OFFER_HOURS = 24                      -- how long a buyer's offer stands
local DELIVERY_HOURS = 6
local COMMON_MODELS = { 'covet', 'pessima', 'vivace', 'etk800', 'sunburst2', 'bastion' }
local STOP_RADIUS = 9

local atMeet       -- (defined further down, used by summary)
-- nothing runs, is sent or is shown on a map that cannot host it (progression.MAPS has); the code and the save stay
local function career() return sl_career and sl_career.isActive() and sl_career.has('classifieds') and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) if ui_message then ui_message(text, 5, 'streetLegal') end end
local function now(s) return (s.day or 0) * 24 + math.floor(sl_career.hour and sl_career.hour() or 12) end
local function state(s)
  s.market = s.market or { listings = {}, nextId = 1, refreshed = -1e9, deliveries = {}, rounds = {} }
  s.market.mine = s.market.mine or {}
  return s.market
end

-- what a shelf part is worth to a buyer: its value, but never more than the shop charges for it (Wrench Works'
-- price setting can make parts cheap; then buying new to sell here must not pay)
local function worth(it) return math.min(it.value or 0, it.price or it.value or 0) end

local NAMES = { 'Dave', 'Kenny', 'Mirela', 'Gabor', strings.t('classifieds.big_tony'), 'Sanja', 'Rudi', 'Lex', strings.t('classifieds.old_man_fekete'), 'Zsofi', 'Marco', 'Petra' }

-- The picture and the words of a part ad (T39; sl/core/partinfo): BeamNG has no picture file for a part, so the ad shows the car it
-- fits (its own preview) with the part's category icon, and the part's real display name and catalog chapter.
local catalogCache
local function catalog()
  if catalogCache == nil then
    local ok, c = pcall(require, 'slrr/garageCatalog')
    catalogCache = ok and type(c) == 'table' and c or false
  end
  return catalogCache or nil
end
local picturesCache
local function pictures()
  if picturesCache == nil then
    picturesCache = false
    local ok, j = pcall(function() return jsonReadFile and jsonReadFile(partinfo.PICTURE_DIR .. 'manifest.json') end)
    if ok and type(j) == 'table' and type(j.parts) == 'table' then
      picturesCache = {}
      for _, name in ipairs(j.parts) do picturesCache[name] = true end
      for part, canon in pairs(type(j.alias) == 'table' and j.alias or {}) do if type(canon) == 'string' then picturesCache[part] = canon end end
    end
  end
  return picturesCache or nil
end
local modelCache = {}
local function modelInfo(model)
  if modelCache[model] then return modelCache[model] end
  local info = { name = tostring(model), preview = nil }
  local ok, m = pcall(function() return core_vehicles.getModel(model) end)
  local mm = ok and type(m) == 'table' and (m.model or m) or nil
  if mm then
    local name = tostring(mm.Name or model)
    info = { name = (mm.Brand and not name:find(tostring(mm.Brand), 1, true)) and (tostring(mm.Brand) .. ' ' .. name) or name, preview = mm.preview }
  end
  modelCache[model] = info
  return info
end
local function partFields(card, item)
  if type(item) ~= 'table' then return card end
  local d = partinfo.describe(item, catalog())
  local mi = modelInfo(item.model or card.model)
  card.name, card.category, card.categoryTitle, card.chapter = d.name, d.category, d.categoryTitle, d.chapter
  card.fits, card.preview = mi.name, mi.preview
  card.partPic = partinfo.picture(item.part, pictures())          -- the part's own picture, where the mod ships one
  return card
end

-- a part's shop card fields (name, category, chapter, the car it fits, pictures): the same for the phone's ads, the laptop's market and its shelf
function M.partCard(item, model)
  return partFields({ model = model }, { part = item.part, name = item.name, slotId = item.slotId, model = model })
end

-- parts of a model with their values (BeamNG's jbeam), cached per model
local partsCache = {}
local function partsOf(model)
  if partsCache[model] then return partsCache[model] end
  local list = {}
  local ok = pcall(function()
    local ctx = jbeamIO.startLoading({ '/vehicles/' .. model .. '/', '/vehicles/common/' })
    for name, desc in pairs(jbeamIO.getAvailableParts(ctx) or {}) do
      if not desc.isAuxiliary then
        local part = jbeamIO.getPart(ctx, name)
        local info = part and part.information or {}
        local value = tonumber(info.value) or 0
        local slot = part and (type(part.slotType) == 'table' and part.slotType[1] or part.slotType)
        if value >= 20 and type(slot) == 'string' and slot ~= 'main' then
          list[#list + 1] = { kind = 'part', part = name, name = partinfo.text(info.name) or partinfo.text(desc.description) or name, value = value, slotId = slot, model = model }
        end
      end
    end
  end)
  if not ok then list = {} end
  table.sort(list, function(a, b) return a.part < b.part end)
  partsCache[model] = list
  return list
end

local function models(s)
  local out, seen = {}, {}
  for _, c in ipairs(s.cars or {}) do if c.model and not seen[c.model] then seen[c.model] = true out[#out + 1] = c.model end end
  for _, m in ipairs(COMMON_MODELS) do if not seen[m] and FS:directoryExists('/vehicles/' .. m .. '/') then seen[m] = true out[#out + 1] = m end end
  return out
end

-- the most a buyer pays for one of your cars: what the lot's own buyers would (market.resaleValue, with the
-- parts it has now) and never more than the least a car like it can be had for on the market
local function carById(s, id) for _, c in ipairs(s.cars or {}) do if c.id == id then return c end end end
local function carCap(s, carId)
  local car = carById(s, carId)
  if not car then return nil end
  local veh = sl_fleet and sl_fleet.vehicleOf and sl_fleet.vehicleOf(carId)
  local partsNow = veh and builder.partsValue(veh:getID()) or nil
  return math.floor(math.min(market.resaleValue(car, partsNow), L.resaleCap(car.value or 0, car.condition or 0.5)) / 10) * 10
end

-- drop what expired, top the app up to APP_LISTINGS, deliver what has arrived
local function refresh(s, force)
  local m, t = state(s), now(s)
  for i = #m.deliveries, 1, -1 do
    local d = m.deliveries[i]
    if d.due <= t then
      table.remove(m.deliveries, i)
      if slrr_garage and slrr_garage.addShelfPart then
        slrr_garage.addShelfPart(d.model, d.part)
        toast(string.format(strings.t('classifieds.delivered_to_your_garage_s'), d.part.name, d.model))
      end
    end
  end
  if not force and t - m.refreshed < REFRESH_HOURS then return end
  m.refreshed = t
  local keep = {}
  -- a taken one stays only while its pickup is the job you are on (bought for delivery, given up: gone)
  local active = s.jobs and s.jobs.active
  for _, l in ipairs(m.listings) do      -- (auction lots: the hourly auctions() settles and removes them)
    if (l.expires > t and not l.taken) or (l.taken and active and active.listing == l.id) or l.channel == 'auction' then keep[#keep + 1] = l end
  end
  m.listings = keep
  local rng = rngLib.new(rngLib.hash('market:' .. t .. ':' .. tostring(s.seed)))
  local ms = models(s)
  local function count(ch) local n = 0 for _, l in ipairs(m.listings) do if l.channel == ch and not l.taken then n = n + 1 end end return n end
  local function add(ch)
    local pool = #ms > 0 and partsOf(ms[rng:int(#ms)]) or {}
    if #pool == 0 then return end
    local l = L.listing(rng, pool[rng:int(#pool)], ch, L.demand(rng), t)
    l.id, l.seller = 'm' .. m.nextId, NAMES[rng:int(#NAMES)]
    m.nextId = m.nextId + 1
    if ch == 'auction' then
      l.bid, l.aiMax = l.ask, math.floor(L.fair(l.item.value, l.condition) * rng:range(0.55, 1.05))
    else
      local k = sl_jobs and sl_jobs.randomKerb and sl_jobs.randomKerb(rng)
      if not k then return end
      l.where = { x = k.x, y = k.y, z = k.z }
      l.printOnly = ch == 'paper' and rng:float() < PRINT_ONLY or nil
    end
    m.listings[#m.listings + 1] = l
  end
  for _, y in ipairs(m.mine) do        -- buyers for your Revline listings (lowballers too); an offer stands a day
    if y.channel == 'app' then
      local keepOffers = {}
      for _, o in ipairs(y.offers) do if t - o.hour < OFFER_HOURS then keepOffers[#keepOffers + 1] = o end end
      y.offers = keepOffers
      if #y.offers < 3 and rng:float() < 0.6 then
        local amount = y.kind == 'car' and L.offerUpTo(rng, carCap(s, y.carId) or 0) or L.buyerOffer(rng, y.value, y.condition)
        local o = { amount = amount, hour = t, buyer = NAMES[rng:int(#NAMES)] }
        y.offers[#y.offers + 1] = o
        toast(string.format(strings.t('classifieds.revline_s_offers_d_for'), o.buyer, o.amount, y.name))
      end
    end
  end
  local function carAds() local n = 0 for _, l in ipairs(m.listings) do if l.kind == 'car' and not l.taken and not l.barn then n = n + 1 end end return n end
  -- private cars: the used lot's kind of car, sold from a kerb. One draw of many different cars (B60: a draw of one gave the lot's cheapest
  -- car every time, the same model for every ad)
  local fresh = sl_lot and sl_lot.privateOffers and sl_lot.privateOffers(rng:int(1, 1000000), CAR_ADS * 3) or {}
  local listed = {}
  for _, l in ipairs(m.listings) do if l.kind == 'car' and not l.taken and l.offer then listed[l.offer.config or l.offer.model] = true end end
  for i = 1, #fresh do
    if carAds() >= CAR_ADS then break end
    local offer = fresh[i]
    if listed[offer.config or offer.model] then offer = nil end
    if offer then listed[offer.config or offer.model] = true end
    local k = offer and sl_jobs and sl_jobs.randomKerb and sl_jobs.randomKerb(rng)
    if k then
      local l = L.listing(rng, { kind = 'car', name = offer.name, value = offer.value or 0, model = offer.model, condition = offer.condition }, 'app', L.demand(rng), t)
      l.id, l.seller, l.offer, l.where = 'm' .. m.nextId, NAMES[rng:int(#NAMES)], offer, { x = k.x, y = k.y, z = k.z }
      m.nextId = m.nextId + 1
      m.listings[#m.listings + 1] = l
    end
  end
  for _ = 1, 40 do if count('app') >= APP_LISTINGS then break end add('app') end
  for _ = 1, 20 do if count('auction') >= AUCTIONS then break end add('auction') end
  local edition = math.floor((s.day or 0) / 7)
  if m.edition ~= edition then         -- a new week, a new paper: last week's ads are gone
    m.edition = edition
    local fresh = {}
    for _, l in ipairs(m.listings) do if l.channel ~= 'paper' or l.taken then fresh[#fresh + 1] = l end end
    m.listings = fresh
  end
  -- the swap meet: stalls on the weekend (days 6 and 7 of the week) at the Tuning shop lot, bought there and then
  local weekend = (s.day or 0) % 7 >= 5
  if not weekend or m.meetDay ~= s.day then
    local others = {}
    for _, l in ipairs(m.listings) do if l.channel ~= 'meet' then others[#others + 1] = l end end
    m.listings = others
  end
  if weekend and m.meetDay ~= s.day and sl_career.has('swapMeet') then
    m.meetDay = s.day
    for _ = 1, MEET_STALLS do
      local pool = #ms > 0 and partsOf(ms[rng:int(#ms)]) or {}
      if #pool > 0 then
        local l = L.listing(rng, pool[rng:int(#pool)], 'paper', L.demand(rng), t)     -- (priced as the paper: no scams in person)
        l.scam, l.noShow = nil, nil
        l.channel, l.id, l.seller = 'meet', 'm' .. m.nextId, NAMES[rng:int(#NAMES)]
        m.nextId = m.nextId + 1
        m.listings[#m.listings + 1] = l
      end
    end
  end
  -- the edition's ads come out through the week (each lasts a day), so the paper is never empty
  for _ = 1, 30 do if count('paper') >= PAPER_LISTINGS then break end add('paper') end
  extensions.hook('onStreetLegalChanged')
end

-- auctions, every in-game hour: the AI bidders have a go; a lot that ends goes to the highest bidder
local function auctions(s)
  local m, t = state(s), now(s)
  if not m.auctionHour or m.auctionHour >= t then m.auctionHour = m.auctionHour or t return end
  m.auctionHour = t
  local rng = rngLib.new(rngLib.hash('bids:' .. t .. ':' .. tostring(s.seed)))
  for i = #m.mine, 1, -1 do             -- your lots: bidders up to what a buyer would pay; sold at the last bid
    local y = m.mine[i]
    if y.channel == 'auction' then
      local cap = L.resaleCap(y.value, y.condition)
      if t < y.expires then
        if rng:float() < 0.5 then
          local b = (y.bid or 0) == 0 and math.floor(cap * 0.4 / 10) * 10 or L.nextBid(rng, y.bid, cap)
          if b and b > 0 then y.bid = b end
        end
      else
        table.remove(m.mine, i)
        if (y.bid or 0) > 0 then
          local got = L.proceeds(y.bid)
          sl_career.addMoney(got, strings.t('classifieds.swap_bid_sale_1', (y.name)))
          toast(string.format(strings.t('classifieds.your_s_sold_for_d'), y.name, y.bid, got))
        else
          if slrr_garage and slrr_garage.putShelfItem then slrr_garage.putShelfItem(y.model, y.item) end
          toast(string.format(strings.t('classifieds.no_bids_on_your_s'), y.name))
        end
      end
    end
  end
  for i = #m.listings, 1, -1 do
    local l = m.listings[i]
    if l.channel == 'auction' then
      if t < l.expires then
        if l.high ~= 'ai' and rng:float() < 0.5 then
          local b = L.nextBid(rng, l.bid, l.aiMax)
          if b then
            l.bid, l.high = b, 'ai'
            if l.watched then toast(string.format(strings.t('classifieds.outbid_on_the_s_now'), l.item.name, b)) end
          end
        end
      else
        table.remove(m.listings, i)
        if l.high == 'you' then
          if sl_career.addMoney(-(l.bid + L.delivery(l.bid)), strings.t('classifieds.swap_bid_1', (l.item.name))) then
            m.deliveries[#m.deliveries + 1] = { due = t + DELIVERY_HOURS, model = l.item.model,
              part = { part = l.item.part, name = l.item.name, slotId = l.item.slotId, value = l.bid, wear = l.wear } }
            toast(string.format(strings.t('classifieds.you_won_the_s_for'), l.item.name, l.bid))
          else
            stateLib.addRep(s, -5)        -- (a bid you couldn't pay: the auction house remembers)
            toast(string.format(strings.t('classifieds.you_won_the_s_but'), l.item.name))
          end
        end
      end
    end
  end
end

local function find(m, id) for i, l in ipairs(m.listings) do if l.id == id then return l, i end end end

-- the meet's place (a table) and name; nil when the map has none
local meetCache
local function meetPlace()
  local places = sl_career.getPlaces() or {}
  if meetCache and places[meetCache] then return places[meetCache], meetCache end
  meetCache = swapmeet.pickPlace(places, swapmeet.FIXED)
  return meetCache and places[meetCache] or nil, meetCache
end
-- open now? (the weekend; a night meet only after the phase turned to night)
local function meetOpen(s) return sl_career.has('swapMeet') and swapmeet.isOpen(s.day, sl_career.isNight and sl_career.isNight(), sl_career.has('nightMeet')) end

-- are you at the swap meet (within MEET_REACH of its place)?
atMeet = function()
  local v = getPlayerVehicle(0)
  local p = meetPlace()
  return v and p and p.pos and (v:getPosition() - vec3(p.pos.x, p.pos.y, p.pos.z)):length() < MEET_REACH or false
end

-- the phone's view of the app
function M.summary()
  local s = career()
  if not s then return nil end
  refresh(s)
  local checks = require('sl/core/features').on('usedcheck')
  local m = state(s)
  local edition = m.edition or 0
  local out = { listings = {}, auctions = {}, deliveries = #m.deliveries, meet = { listings = {}, place = (meetPlace() or {}).name or strings.t('classifieds.tuning_shop_lot'), night = sl_career.has('nightMeet') or nil },
    paper = { bought = m.paperRead == edition, edition = edition + 1, listings = {}, hidden = 0, price = L.PAPER_PRICE } }
  for _, l in ipairs(m.listings) do
    if not l.taken and not l.hidden then
      local card = { id = l.id, name = l.item.name, model = l.item.model, ask = l.agreed or l.ask, condition = math.floor(l.condition * 100 + 0.5),
        seller = l.seller, rating = l.rating, tells = L.tells(l), rare = l.rare, agreed = l.agreed ~= nil,
        delivery = not l.scam and L.delivery(l.agreed or l.ask) or nil, deposit = L.deposit(l.agreed or l.ask), hoursLeft = l.expires - now(s) }
      if not (l.kind == 'car' and l.offer) then partFields(card, l.item) end
      if l.kind == 'car' and l.offer then
        card.car, card.mileage, card.faults = true, l.offer.mileage, #(l.offer.faults or {})
        -- as the stock shop lists a car: the config's picture, year, brand, specs, how far away, when it would arrive
        local info = carInfo.of({ id = 'revline:' .. l.id, model = l.offer.model, config = l.offer.config })
        card.preview, card.year, card.specs, card.brand = info.preview, info.year, info.specs, info.brand
        card.faultList = l.offer.faults
        card.report = carreport.build(l.offer)          -- 'Show full car report' (#58)
        if checks and l.channel ~= 'auction' and l.channel ~= 'meet' then          -- used-car checks: the ad tells the history, the faults and the report cost a mechanic's check
          local h = usedcar.history(l.id, l.offer.mileage, l.offer.faults, l.condition)
          card.history, card.checkFee, card.checked = h.lines, usedcar.fee(l.agreed or l.ask), l.checked == true
          if l.checked then card.found = usedcar.faultCosts(l.offer.faults, l.offer.value or l.value, carreport.FAULT_COST)
          else card.faults, card.faultList, card.report, card.hidden = nil, nil, nil, true end
        end
        local v = getPlayerVehicle(0)
        local yard = sl_fleet and sl_fleet.forecourt(s, 0)
        if v and l.where then
          local p = v:getPosition()
          card.metres = math.floor(math.sqrt((p.x - l.where.x) ^ 2 + (p.y - l.where.y) ^ 2))
        end
        if yard and l.where then card.hours = dealersLib.delayHours(math.sqrt((yard.x - l.where.x) ^ 2 + (yard.y - l.where.y) ^ 2)) end
      end
      if l.channel == 'auction' then
        card.bid, card.high, card.next = l.bid, l.high, l.bid + math.max(10, math.floor(l.bid * 0.05 / 10 + 0.5) * 10)
        out.auctions[#out.auctions + 1] = card
      elseif l.channel == 'meet' then
        out.meet.listings[#out.meet.listings + 1] = card
      elseif l.channel == 'paper' then
        if l.printOnly and m.paperRead ~= edition then
          out.paper.hidden = out.paper.hidden + 1
        else
          card.printOnly = l.printOnly
          out.paper.listings[#out.paper.listings + 1] = card
        end
      else
        out.listings[#out.listings + 1] = card
      end
    end
  end
  out.meet.open = meetOpen(s)
  out.meet.here = out.meet.open and atMeet() or false
  out.mine, out.shelf = {}, {}
  for _, y in ipairs(m.mine) do
    local offers = {}
    for k, o in ipairs(y.offers or {}) do offers[#offers + 1] = { index = k, amount = o.amount, buyer = o.buyer } end
    local mineCard = { id = y.id, name = y.name, model = y.model, channel = y.channel, offers = offers, bid = y.bid,
      hoursLeft = y.expires and (y.expires - now(s)) or nil }
    if y.kind == 'car' then mineCard.preview, mineCard.fits, mineCard.category = modelInfo(y.model).preview, modelInfo(y.model).name, 'car'
    else partFields(mineCard, { part = y.item and y.item.part, name = y.name, slotId = y.item and y.item.slotId, model = y.model }) end
    out.mine[#out.mine + 1] = mineCard
  end
  out.cars = {}
  if #m.mine < MINE_MAX then
    local listed = {}
    for _, y in ipairs(m.mine) do if y.carId then listed[y.carId] = true end end
    for _, c in ipairs(s.cars or {}) do
      if not listed[c.id] then out.cars[#out.cars + 1] = { id = c.id, name = c.name, estimate = carCap(s, c.id), preview = modelInfo(c.model).preview, category = 'car' } end
    end
  end
  if slrr_garage and slrr_garage.shelfItems and #m.mine < MINE_MAX then
    local seen = {}
    for _, c in ipairs(s.cars or {}) do
      if c.model and not seen[c.model] then
        seen[c.model] = true
        for _, it in ipairs(slrr_garage.shelfItems(c.model) or {}) do
          if L.canList(it) and #out.shelf < 12 then
            out.shelf[#out.shelf + 1] = partFields({ model = c.model, id = it.id, name = it.name,
              estimate = math.floor(L.resaleCap(worth(it), L.condition(it)) / 10) * 10 }, { part = it.part, name = it.name, slotId = it.slotId, model = c.model })
          end
        end
      end
    end
  end
  return out
end

-- haggle: an offer to the seller; returns ok, text
function M.offer(id, amount)
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local m = state(s)
  local l = find(m, id)
  if not l or l.taken or l.hidden or l.channel == 'auction' or l.channel == 'meet' then return false, strings.t('classifieds.that_listing_is_gone') end   -- (a lot is only bid on; a stall is bought there)
  local r, price = L.haggle(l, amount, m.rounds[id] or 0)
  m.rounds[id] = (m.rounds[id] or 0) + 1
  if r == 'accept' then l.agreed = price return true, string.format(strings.t('classifieds.s_deal_d'), l.seller, price) end
  if r == 'counter' then l.ask = price return true, string.format(strings.t('classifieds.s_can_do_d_no'), l.seller, price) end
  if r == 'walk' then l.expires = now(s) return false, strings.t('classifieds.1_stopped_answering', (l.seller)) end
  return false, string.format(strings.t('classifieds.s_no_chance'), l.seller)
end

-- a barn find (sl_barnfinds): a poor, cheap car in an ad at a remote spot, hidden from the app until the player has found it. Returns the listing id and the car's name, or nil.
function M.addBarn(spot, seed)
  local s = career()
  if not s or not (sl_lot and sl_lot.privateOffers) then return nil end
  local m = state(s)
  local t = now(s)
  local rng = rngLib.new(rngLib.hash('barnad:' .. tostring(seed) .. ':' .. tostring(s.seed)))
  local offer = barnRules.pick(sl_lot.privateOffers(rng:int(1, 1000000), 12))
  if not offer then return nil end
  offer = barnRules.carOffer(offer, rng)
  local l = L.listing(rng, { kind = 'car', name = offer.name, value = offer.value or 0, model = offer.model, condition = offer.condition }, 'app', 1, t)
  l.id, l.seller, l.offer, l.where = 'm' .. m.nextId, strings.t('barn.seller'), offer, { x = spot.x, y = spot.y, z = spot.z or 0 }
  m.nextId = m.nextId + 1
  l.barn, l.hidden, l.rare, l.scam, l.noShow, l.newAccount, l.payNote = true, true, true, nil, nil, false, nil
  l.rating = 4
  l.expires = t + 24 * 30
  l.ask = offer.price
  l.floor = math.max(10, math.floor(offer.price * 0.85 / 10) * 10)
  m.listings[#m.listings + 1] = l
  return l.id, offer.name
end

-- what became of a barn ad: 'open' (still for sale), 'gone' (bought, or taken off the market)
function M.barnState(id)
  local s = career()
  local l = s and find(state(s), id)
  if l and not l.taken then return 'open' end
  return 'gone'
end

function M.revealBarn(id)
  local s = career()
  local l = s and find(state(s), id)
  if not l then return false end
  l.hidden = nil
  extensions.hook('onStreetLegalChanged')
  return true
end

-- a mechanic checks a private ad's car: the faults and the report show from now on. Returns ok, text.
function M.check(id)
  if not require('sl/core/features').on('usedcheck') then return nil end
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local l = find(state(s), id)
  if not l or l.taken or l.hidden or l.kind ~= 'car' or not l.offer or l.channel == 'auction' or l.channel == 'meet' then return false, strings.t('classifieds.that_listing_is_gone') end
  if l.checked then return true, strings.t('usedcar.already_checked') end
  local fee = usedcar.fee(l.agreed or l.ask)
  if not sl_career.addMoney(-fee, strings.t('usedcar.check_label')) then return false, strings.t('career.not_enough_money') end
  l.checked = true
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('usedcar.checked', #(l.offer.faults or {}), fee)
end

-- buy: 'delivery' (pay it all now plus delivery; on the shelf in a few hours) or 'pickup' (a deposit now,
-- the rest at the seller's kerb)
function M.buy(id, how)
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local m = state(s)
  local l = find(m, id)
  if not l or l.taken or l.hidden or l.channel == 'auction' or l.channel == 'meet' then return false, strings.t('classifieds.that_listing_is_gone') end   -- (a lot is only bid on; a stall is bought there)
  local price = l.agreed or l.ask
  local part = { part = l.item.part, name = l.item.name, slotId = l.item.slotId, value = price, wear = l.wear }
  if how == 'delivery' and l.kind == 'car' then
    -- a car comes the way a dealer's does (sl_dealers): paid now with the delivery fee, built at your garage a few hours later
    if l.scam then return false, strings.t('classifieds.1_no_delivery_deposit_by', (l.seller)) end
    local yard = sl_fleet and sl_fleet.forecourt(s, 0)
    if not (yard and l.offer and l.where) then return false, strings.t('classifieds.1_come_and_see_it', (l.seller)) end
    if not sl_career.addMoney(-(price + L.delivery(price)), strings.t('classifieds.revline_1', (l.offer.name))) then return false, strings.t('career.not_enough_money') end
    l.taken = true
    local order = dealersLib.orderPrivate(s, l, price, yard, dealersLib.clock(s.day, sl_career.hour()))
    return true, string.format(strings.t('classifieds.paid_the_s_comes_to'), l.offer.name, order.hours)
  end
  if how == 'delivery' then
    if l.scam then return false, strings.t('classifieds.1_no_delivery_deposit_by', (l.seller)) end
    if not sl_career.addMoney(-(price + L.delivery(price)), strings.t('classifieds.revline_1', (l.item.name))) then return false, strings.t('career.not_enough_money') end
    l.taken = true
    m.deliveries[#m.deliveries + 1] = { due = now(s) + DELIVERY_HOURS, model = l.item.model, part = part }
    return true, string.format(strings.t('classifieds.paid_the_s_comes_to'), l.item.name, DELIVERY_HOURS)
  end
  local js = s.jobs
  if js and js.active then return false, strings.t('classifieds.finish_the_job_you_are') end
  if not (sl_fleet and sl_fleet.currentCar()) then return false, strings.t('classifieds.you_need_to_be_in') end   -- (sl_jobs.take refuses after the deposit otherwise)
  local deposit = L.deposit(price)
  if not sl_career.addMoney(-deposit, strings.t('classifieds.revline_deposit_1', (l.item.name))) then return false, strings.t('classifieds.not_enough_for_the_deposit') end
  l.taken = true
  local w = l.where
  local job = { id = 'market:' .. l.id, kind = 'market', title = strings.t('classifieds.pick_up'), item = l.item.name, settle = 'market', seconds = 0, pay = 0,
    legs = { { id = 'seller', name = l.seller .. strings.t('classifieds.s_place'), x = w.x, y = w.y, z = w.z }, { id = 'seller', name = l.seller .. strings.t('classifieds.s_place'), x = w.x, y = w.y, z = w.z } },
    listing = l.id, price = price, deposit = deposit, model = l.item.model, part = part, scam = l.scam, noShow = l.noShow,
    privateCar = l.kind == 'car' and l.offer or nil, seller = l.seller }
  js = js or { offers = {}, done = 0, earned = 0 }
  s.jobs = js
  js.offers = js.offers or {}
  js.offers[#js.offers + 1] = job
  local ok, text = sl_jobs.take(job.id)
  return ok, ok and string.format(strings.t('classifieds.deposit_d_paid_s_is'), deposit, l.seller) or text
end

-- sell one of your shelf parts: on Revline (buyers make offers) or at auction (sold at the last bid, or back to the
-- shelf). The part leaves the shelf while it is listed; a job car's part can't be listed
function M.listPart(model, itemId, channel)
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local m = state(s)
  if #m.mine >= MINE_MAX then return false, strings.t('classifieds.you_have_1_things_listed', (MINE_MAX)) end
  if not (slrr_garage and slrr_garage.shelfItems) then return false, strings.t('classifieds.wrench_works_is_not_running') end
  local copy
  for _, it in ipairs(slrr_garage.shelfItems(model) or {}) do if it.id == tonumber(itemId) then copy = it end end
  if not copy then return false, strings.t('classifieds.that_part_is_not_on') end
  if not L.canList(copy) then return false, strings.t('classifieds.that_part_belongs_to_a') end
  local item = slrr_garage.takeShelfItem(model, copy.id)
  if not item then return false, strings.t('classifieds.not_while_you_are_in') end
  local t = now(s)
  local y = { id = 'y' .. m.nextId, model = model, name = copy.name, value = worth(copy), condition = L.condition(copy),
    channel = channel == 'auction' and 'auction' or 'app', item = item, offers = {}, listed = t }
  m.nextId = m.nextId + 1
  if y.channel == 'auction' then y.bid, y.expires = 0, t + L.CHANNELS.auction.life end
  m.mine[#m.mine + 1] = y
  extensions.hook('onStreetLegalChanged')
  if y.channel == 'auction' then return true, string.format(strings.t('classifieds.your_s_is_up_for'), y.name, L.CHANNELS.auction.life) end
  return true, string.format(strings.t('classifieds.your_s_is_on_revline_2'), y.name)
end

local function findMine(m, id) for i, y in ipairs(m.mine) do if y.id == id then return y, i end end end

-- sell one of your cars on Revline: it stays yours (and drivable) until you accept an offer
function M.listCar(carId)
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local m = state(s)
  if #m.mine >= MINE_MAX then return false, strings.t('classifieds.you_have_1_things_listed', (MINE_MAX)) end
  local car = carById(s, tonumber(carId) or carId)
  if not car then return false, strings.t('classifieds.that_car_is_not_yours') end
  for _, y in ipairs(m.mine) do if y.carId == car.id then return false, strings.t('classifieds.it_is_listed_already') end end
  local y = { id = 'y' .. m.nextId, kind = 'car', carId = car.id, name = car.name or car.model, model = car.model, value = car.value or 0,
    condition = car.condition or 0.5, channel = 'app', offers = {}, listed = now(s) }
  m.nextId = m.nextId + 1
  m.mine[#m.mine + 1] = y
  extensions.hook('onStreetLegalChanged')
  return true, string.format(strings.t('classifieds.your_s_is_on_revline'), y.name)
end

-- onPrivateSold: sl_lot sold you a Revline car (the listing went when the seller showed it)
function M.onPrivateSold(listingId, carId)
  extensions.hook('onStreetLegalChanged')
end

function M.acceptOffer(id, index)
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local m = state(s)
  local y, i = findMine(m, id)
  local o = y and y.offers[tonumber(index) or 0]
  if not o then return false, strings.t('classifieds.that_offer_is_gone') end
  local amount, sold = o.amount, nil
  if y.kind == 'car' then
    local cap = carCap(s, y.carId)
    if not cap then table.remove(m.mine, i) return false, strings.t('classifieds.that_car_is_not_yours') end
    if amount > cap then               -- (the buyer sees the car as it is now: stripped or bent since, it is worth less)
      o.amount = cap
      return false, string.format(strings.t('classifieds.s_had_a_look_at'), o.buyer or strings.t('classifieds.the_buyer'), cap)
    end
    sold = carById(s, y.carId)
    local _, veh = sl_fleet.lose(y.carId)
    if veh then veh:delete() end          -- (the buyer drives it away: as sl_fleet.sell does)
  end
  table.remove(m.mine, i)
  local got = L.proceeds(amount)
  sl_career.addMoney(got, strings.t('classifieds.revline_sale_1', (y.name)))
  if sold then extensions.hook('onStreetLegalCarSold', sold, got, 'revline') end     -- (the flip challenge counts it)
  extensions.hook('onStreetLegalChanged')
  return true, string.format(strings.t('classifieds.sold_the_s_to_s'), y.name, o.buyer or strings.t('ui.a_buyer'), got)
end

-- a career slot about to be deleted (sl_career): its listed parts go back on the Wrench Works shelf, which every
-- slot shares, so nothing listed is lost with the slot. s: that slot's state
function M.returnListed(s)
  local m = type(s) == 'table' and s.market
  if not m or not m.mine then return 0 end
  local n = 0
  for _, y in ipairs(m.mine) do
    if y.item and slrr_garage and slrr_garage.putShelfItem and slrr_garage.putShelfItem(y.model, y.item) then n = n + 1 end   -- (a car never left)
  end
  m.mine = {}
  return n
end

function M.withdraw(id)
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local m = state(s)
  local y, i = findMine(m, id)
  if not y then return false, strings.t('classifieds.that_listing_is_gone') end
  if y.channel == 'auction' and (y.bid or 0) > 0 then return false, strings.t('classifieds.there_are_bids_on_it') end
  table.remove(m.mine, i)
  if y.kind == 'car' then extensions.hook('onStreetLegalChanged') return true, string.format(strings.t('classifieds.your_s_is_off_revline'), y.name) end
  if slrr_garage and slrr_garage.putShelfItem then slrr_garage.putShelfItem(y.model, y.item) end
  extensions.hook('onStreetLegalChanged')
  return true, string.format(strings.t('classifieds.your_s_is_back_on'), y.name)
end

-- buy at a swap meet stall: there and then, at the asking price, straight onto your shelf
function M.buyAtMeet(id)
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local m = state(s)
  local l, i = find(m, id)
  if not l or l.channel ~= 'meet' then return false, strings.t('classifieds.that_stall_has_sold_it') end
  if not meetOpen(s) then return false, strings.t('classifieds.the_swap_meet_runs_on', (sl_career.has('nightMeet') and ' nights' or '')) end
  if not atMeet() then return false, string.format(strings.t('classifieds.the_swap_meet_is_at'), (meetPlace() or {}).name or strings.t('classifieds.tuning_shop_lot')) end
  if not (slrr_garage and slrr_garage.addShelfPart) then return false, strings.t('classifieds.you_need_wrench_works_running') end
  if not sl_career.addMoney(-l.ask, strings.t('classifieds.swap_meet_1', (l.item.name))) then return false, strings.t('career.not_enough_money') end
  table.remove(m.listings, i)
  if slrr_garage and slrr_garage.addShelfPart then
    slrr_garage.addShelfPart(l.item.model, { part = l.item.part, name = l.item.name, slotId = l.item.slotId, value = l.ask, wear = l.wear })
  end
  extensions.hook('onStreetLegalChanged')
  return true, string.format(strings.t('classifieds.bought_the_s_from_s'), l.item.name, l.seller, l.item.model)
end

-- Swap & Bid: bid the next step on a lot (paid when it ends, if you are still the highest bidder)
function M.bid(id)
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local l = find(state(s), id)
  if not l or l.channel ~= 'auction' or l.expires <= now(s) then return false, strings.t('classifieds.that_auction_is_over') end
  if l.high == 'you' then return false, strings.t('classifieds.you_are_the_highest_bidder') end
  local nb = l.bid + math.max(10, math.floor(l.bid * 0.05 / 10 + 0.5) * 10)
  if (s.money or 0) < nb + L.delivery(nb) then return false, strings.t('classifieds.you_could_not_pay_that') end
  l.bid, l.high, l.watched = nb, 'you', true
  extensions.hook('onStreetLegalChanged')
  return true, string.format(strings.t('classifieds.your_bid_d_on_the'), nb, l.item.name)
end

-- the printed paper: $2 at a gas station; this week's print-only ads show on the phone after that
function M.buyPaper()
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local m = state(s)
  if m.paperRead == m.edition then return false, strings.t('classifieds.you_have_this_week_s') end
  local v = getPlayerVehicle(0)
  local here = v and v:getPosition()
  local near = false
  local f = freeroam_facilities and freeroam_facilities.getFacilities and freeroam_facilities.getFacilities(getCurrentLevelIdentifier())
  for _, g in ipairs(f and f.gasStations or {}) do      -- (the game's own gas stations, as sl_jobs' diners)
    local c = freeroam_gasStations and freeroam_gasStations.gasStationCenterRadius and freeroam_gasStations.gasStationCenterRadius(g)
    if c and here and (here - vec3(c.x, c.y, c.z)):length() < PAPER_REACH then near = true end
  end
  if not near then return false, strings.t('classifieds.pick_up_a_copy_at') end
  if not sl_career.addMoney(-L.PAPER_PRICE, sl_career.mapText(strings.t('classifieds.valo_classifieds'))) then return false, strings.t('classifieds.not_even_2') end
  m.paperRead = m.edition
  extensions.hook('onStreetLegalChanged')
  return true, sl_career.mapText(strings.t('classifieds.this_week_s_valo_classifieds'))
end

-- the pickup: at the seller's kerb, slow - pay the rest and the part goes on the shelf (or not, if it was a scam
-- or nobody comes out)
local timer = 0
function M.onUpdate(dtReal)
  local s = career()
  if not s then return end
  timer = timer + (dtReal or 0)
  if timer < 0.5 then return end
  timer = 0
  refresh(s)
  auctions(s)
  local js = s.jobs
  local j = js and js.active
  if not j or j.settle ~= 'market' then return end
  local v = getPlayerVehicle(0)
  if not v then return end
  local stop = j.legs[1]
  if (v:getPosition() - vec3(stop.x, stop.y, stop.z or 0)):length() > STOP_RADIUS or v:getVelocity():length() > 2 then return end
  local m = state(s)
  if j.privateCar and not j.scam and not j.noShow then
    -- a car: the deposit back, and the seller shows it to you (sl_lot's private sale: look, test drive, buy at the price agreed)
    local offer = deepcopy(j.privateCar)
    offer.price, offer.listingId = j.price, j.listing
    if not (sl_lot and sl_lot.openPrivate and sl_lot.openPrivate(offer, vec3(stop.x, stop.y, stop.z or 0), j.seller)) then
      if not j.waitTold then toast(strings.t('classifieds.close_the_lot_screen_you')) j.waitTold = true end
      return
    end
    sl_career.addMoney(j.deposit, strings.t('classifieds.revline_deposit_back'))
    local _, i = find(m, j.listing)
    if i then table.remove(m.listings, i) end
    sl_jobs.cancel(s, js, j, string.format(strings.t('classifieds.s_shows_you_the_s'), j.seller or strings.t('classifieds.the_seller'), j.item))
    return
  end
  local _, i = find(m, j.listing)
  if i then table.remove(m.listings, i) end
  if j.scam then
    sl_jobs.cancel(s, js, j, string.format(strings.t('classifieds.nobody_here_has_heard_of'), (stop.name:gsub("'s place", '')), j.deposit))
  elseif j.noShow then
    sl_career.addMoney(j.deposit, strings.t('classifieds.revline_deposit_back'))
    sl_jobs.cancel(s, js, j, strings.t('classifieds.nobody_came_out_the_deposit'))
  elseif not sl_career.addMoney(-(j.price - j.deposit), strings.t('classifieds.revline_1', (j.item))) then
    toast(string.format(strings.t('classifieds.the_seller_wants_d_more'), j.price - j.deposit))
    return
  else
    if slrr_garage and slrr_garage.addShelfPart then slrr_garage.addShelfPart(j.model, j.part) end
    sl_jobs.cancel(s, js, j, string.format(strings.t('classifieds.got_the_s_it_is'), j.item, j.model))
  end
end

-- (the Mods menu's Parts of the game: with this part off, the hooks above do nothing)
require('sl/core/features').gate('market', M)

return M
