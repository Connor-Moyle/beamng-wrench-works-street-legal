-- Wrench Works: Street Legal: car auctions (extension name: sl_carauctions; rules in sl/core/carauction, design note to connor-62 2026-10-18)
-- The online auction on the laptop and the phone: six lots of used cars with a grade, the car report, a hidden reserve and AI bidders; a lot closes
-- on the game clock (1 to 2 game days), the bidders move as game time passes, the hammer takes the money and the car is delivered by the same order as
-- a dealer's car (sl/core/dealers). A car may hide a fault the report does not show: it is found after the purchase. You can put one of your own
-- cars up too. The lots and their bidders are in the career save (s.auction).

local M = {}

local strings = require('sl/core/strings')
local rules = require('sl/core/carauction')
local dealerRules = require('sl/core/dealers')
local market = require('sl/core/market')
local rngLib = require('sl/core/rng')
local listings = require('sl/core/listings')
local carInfo = require('sl/carInfo')
local carreport = require('sl/core/carreport')

local LOTS = 6                 -- on the screen at once
local HOURS = { 12, 40 }       -- a lot closes this many game hours after it opens
local MAX_CATCHUP = 3000       -- lot-clock steps in one call (a long Wait)

local yard, liveLot      -- the live yard session and its current lot (below)
local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function now(s) return dealerRules.clock(s.day, sl_career.hour()) end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end

local function state(s)
  s.auction = s.auction or { lots = {}, mine = {}, nextId = 1 }
  return s.auction
end

-- the lot yard's cars: the junkyard's own pool, so what is on the auction is what the map sells used
local function pool()
  for _, p in pairs(sl_career.getPlaces() or {}) do
    if p.kind == 'junkyard' and sl_lot and sl_lot.poolOf then return sl_lot.poolOf(p) end
  end
  return {}
end

local function fill(s, m, t)
  local missing = LOTS - #m.lots
  if missing <= 0 then return end
  local rng = rngLib.new(rngLib.hash('auction:' .. t .. ':' .. m.nextId .. ':' .. tostring(s.seed)))
  local offers = market.offers(pool(), 'used', tostring(s.seed) .. ':auction:' .. m.nextId, s.day, missing + 4)
  for _, offer in ipairs(offers) do
    if #m.lots >= LOTS then break end
    offer.id = 'auction:' .. m.nextId
    local lot = rules.newLot(rng, offer, t, t + rng:range(HOURS[1], HOURS[2]))
    lot.id, lot.lastT = 'a' .. m.nextId, t
    m.nextId = m.nextId + 1
    m.lots[#m.lots + 1] = lot
  end
end

-- the lot clock follows the game clock: game minutes since the last look, in steps of one
local function advance(lot, t, rng)
  local minutes = math.min(MAX_CATCHUP, math.floor((t - (lot.lastT or t)) * 60))
  if minutes <= 0 then return end
  lot.lastT = (lot.lastT or t) + minutes / 60
  for _ = 1, minutes do
    if not lot.open then break end
    rules.step(lot, 1, rng)
  end
end

local function carName(offer) return offer.name or offer.model or '?' end

-- a lot closed: you won (the money at the hammer, the car on its way) or it went to someone else
local function settleBuy(s, m, lot, t)
  local r = rules.result(lot)
  local name = carName(lot.offer)
  if r.sold == 'you' then
    local fee = rules.delivery(r.price)
    if sl_career.addMoney(-(r.price + fee), string.format(strings.t('carauction.paid_1'), name)) then
      local offer = {}
      for k, v in pairs(lot.offer) do offer[k] = v end
      offer.price = r.price
      if r.hidden then
        offer.faults = { table.unpack(offer.faults or {}) }
        offer.faults[#offer.faults + 1] = r.hidden.fault
        offer.foundFault = { key = r.hidden.key, cost = r.hidden.cost }      -- (told when it is delivered)
      end
      dealerRules.place(s, offer, 'auction', 4000, t)      -- (delivered like a dealer's car, as if 4 km away)
      toast(string.format(strings.t('carauction.you_won_the_s_for'), name, r.price, fee))
      extensions.hook('onStreetLegalChanged')
    else
      require('sl/core/state').addRep(s, -5)      -- (a bid you couldn't pay: the auction house remembers)
      toast(string.format(strings.t('carauction.you_won_the_s_but'), name))
    end
  elseif lot.high == 'you' and r.sold == 'reserve' then
    toast(string.format(strings.t('carauction.the_reserve_on_the_s'), name))
  elseif lot.watched then
    toast(string.format(strings.t('carauction.the_s_went_to_another'), name, r.price))
  end
end

-- your own car at auction closed
local function settleSale(s, m, lot)
  local sale = lot.mine
  local r = rules.result(lot)
  local carId = lot.carId
  local car
  for _, c in ipairs(s.cars or {}) do if c.id == carId then car = c end end
  if not car then toast(string.format(strings.t('carauction.the_s_was_not_there'), carName(lot.offer))) return end
  if r.sold == 'ai' then
    local got = rules.sellProceeds(lot)
    local car2, veh = sl_fleet.lose(carId)
    if veh then veh:delete() end
    sl_career.addMoney(got, string.format(strings.t('carauction.sold_1'), carName(lot.offer)))
    toast(string.format(strings.t('carauction.your_s_sold_for_d'), carName(lot.offer), r.price, got))
  else
    car.atAuction = nil
    toast(string.format(strings.t('carauction.your_s_did_not_sell'), carName(lot.offer), r.sold == 'none' and strings.t('carauction.no_bids') or strings.t('carauction.reserve_not_met')))
  end
end

local function tick(s)
  local m = state(s)
  local t = now(s)
  local rng = rngLib.new(rngLib.hash('bids:' .. math.floor(t * 60) .. ':' .. tostring(s.seed)))
  for i = #m.lots, 1, -1 do
    local lot = m.lots[i]
    advance(lot, t, rng)
    if not lot.open then
      table.remove(m.lots, i)
      settleBuy(s, m, lot, t)
    end
  end
  for i = #m.mine, 1, -1 do
    local lot = m.mine[i]
    advance(lot, t, rng)
    if not lot.open then
      table.remove(m.mine, i)
      settleSale(s, m, lot)
    end
  end
  fill(s, m, t)
  for _, l in ipairs(rules.watchDue(m.lots, t)) do
    l.told = true
    sl_career.sendText('benny', string.format(strings.t('carauction.the_s_closes_in_ten'), carName(l.offer)), 2)
  end
end

-- ---- what the screens see
local function card(lot, t)
  local o = lot.offer
  local info = carInfo.of(o)
  local left = math.max(0, lot.closesAt - lot.t)      -- (online: the lot clock is game minutes)
  return { id = lot.id, name = carName(lot.offer), brand = info.brand or o.brand, year = info.year, specs = info.specs, preview = info.preview,
    mileage = o.mileage, grade = lot.grade, condition = math.floor(lot.condition * 100 + 0.5), faults = o.faults or {},
    report = carreport.build(o), bid = lot.bid, next = rules.nextMin(lot), high = lot.high == 'you' and 'you' or (lot.high and 'ai' or nil),
    reserveMet = rules.reserveMet(lot), bids = lot.bids, minutesLeft = math.ceil(left), watched = lot.watched or nil, mine = lot.mine or nil,
    reserve = lot.mine and lot.reserve or nil, delivery = lot.live and 0 or rules.delivery(math.max(lot.bid, lot.opening)),
    live = lot.live or nil, secondsLeft = lot.live and math.ceil(math.max(0, lot.closesAt - lot.t)) or nil }
end

local viewing = false      -- a screen shows the lots: the ticks push them (the lots move while you look)
function M.view(on) viewing = on == true if viewing then M.list() end end

function M.list()
  local s = career()
  if not s then return end
  local m = state(s)
  tick(s)
  local t = now(s)
  local out = { lots = {}, mine = {}, money = s.money, sellable = M.sellable() }
  for _, l in ipairs(m.lots) do out.lots[#out.lots + 1] = card(l, t) end
  for _, l in ipairs(m.mine) do out.mine[#out.mine + 1] = card(l, t) end
  local y = liveLot()
  if y then out.live = { index = yard.idx, total = #yard.lots, lot = card(y, t), waiting = not y.open or yard.gap > 0 } end
  guihooks.trigger('slAuctions', out)
  return out
end

-- ---- the weekly auction at the junkyard: six lots one after the other, each open for rules.DURATION real seconds
local YARD = { weekday = 5, from = 10, to = 13, lots = 6, gap = 4 }      -- every 7th day, 10:00-13:00
-- (yard: the session { day, lots, idx, gap, rng, pushT })

function M.yardOpen()
  local s = career()
  if not s or (sl_career.isNight and sl_career.isNight()) then return false end
  local h = sl_career.hour()
  if (s.day or 0) % 7 ~= YARD.weekday or h < YARD.from or h >= YARD.to then return false end
  return not (state(s).yardDone == s.day)
end

liveLot = function() return yard and yard.lots[yard.idx] end

local function find(m, id)
  for _, l in ipairs(m.lots) do if l.id == id then return l end end
  local y = liveLot()
  if y and y.id == id and y.open then return y end
end

-- you bid (amount: the most you will pay now; at least the minimum bid)
function M.bid(id, amount)
  local s = career()
  if not s then return false end
  local m = state(s)
  tick(s)
  local lot = find(m, tostring(id))
  if not lot then toast(strings.t('carauction.that_lot_is_closed')) M.list() return false end
  amount = tonumber(amount) or rules.nextMin(lot)
  local ok, why = rules.youBid(lot, amount, s.money)
  local texts = { low = 'carauction.too_low', cash = 'carauction.not_enough_cash', yours = 'carauction.you_are_the_highest', closed = 'carauction.that_lot_is_closed' }
  if not ok then toast(string.format(strings.t(texts[why] or 'carauction.that_lot_is_closed'), rules.nextMin(lot))) end
  M.list()
  return ok
end

function M.watch(id, on)
  local s = career()
  local lot = s and find(state(s), tostring(id))
  if not lot then return false end
  lot.watched = on ~= false and on ~= 0 or nil
  if not lot.watched then lot.told = nil end
  M.list()
  return true
end

-- your cars that can be put up: at the garage's care, not already up, not in a pending sale
function M.sellable()
  local s = career()
  if not s then return {} end
  local out = {}
  for _, c in ipairs(s.cars or {}) do
    if not c.atAuction and not c.impounded then
      local cond = c.condition or 0.6
      out[#out + 1] = { id = c.id, name = c.name or c.model, condition = cond, grade = rules.grade(cond), fair = math.floor(listings.fair(c.value, cond)) }
    end
  end
  return out
end

function M.sell(carId, reserve)
  local s = career()
  if not s then return false end
  local m = state(s)
  local car
  for _, c in ipairs(s.cars or {}) do if c.id == carId then car = c end end
  if not car or car.atAuction or car.impounded then toast(strings.t('carauction.you_cannot_sell_that_one')) return false end
  if #(s.cars or {}) <= 1 then toast(strings.t('carauction.keep_one_car')) return false end
  local t = now(s)
  local rng = rngLib.new(rngLib.hash('sell:' .. m.nextId .. ':' .. tostring(s.seed)))
  local lot = rules.sellLot(rng, { name = car.name, model = car.model, brand = car.brand, value = car.value, condition = car.condition or 0.6,
    mileage = car.mileage, faults = car.faults }, tonumber(reserve), t, t + rng:range(HOURS[1], HOURS[2]))
  lot.id, lot.lastT, lot.carId = 'm' .. m.nextId, t, carId
  m.nextId = m.nextId + 1
  car.atAuction = true
  m.mine[#m.mine + 1] = lot
  toast(string.format(strings.t('carauction.your_s_is_up_for'), carName(lot.offer), lot.reserve))
  M.list()
  return true
end

-- you walk up to the yard on auction day: the session starts (or goes on), the phone shows the live lots
function M.join()
  local s = career()
  if not s or not M.yardOpen() then return false end
  if not yard or yard.day ~= s.day then
    local rng = rngLib.new(rngLib.hash('yard:' .. tostring(s.day) .. ':' .. tostring(s.seed)))
    local offers = market.offers(pool(), 'used', tostring(s.seed) .. ':yard', s.day, YARD.lots + 4)
    yard = { day = s.day, lots = {}, idx = 1, gap = 2, rng = rng, pushT = 0 }
    for i, offer in ipairs(offers) do
      if #yard.lots >= YARD.lots then break end
      offer.id = 'yard:' .. s.day .. ':' .. i
      local lot = rules.newLot(rng, offer, now(s))
      lot.id, lot.live = 'y' .. s.day .. '_' .. i, true
      yard.lots[#yard.lots + 1] = lot
    end
    toast(strings.t('carauction.the_auction_starts'))
  end
  guihooks.trigger('slPhoneGo', { app = 'carmarket', tabs = { cars = 'auction' } })
  viewing = true
  M.list()
  return true
end

function M.leaveYard() yard = nil end

-- a live lot closed: the hammer (the car is handed over at the yard: no delivery fee, it is at your garage soon)
local function settleLive(s, lot)
  local r = rules.result(lot)
  local name = carName(lot.offer)
  if r.sold == 'you' then
    if sl_career.addMoney(-r.price, string.format(strings.t('carauction.paid_1'), name)) then
      local offer = {}
      for k, v in pairs(lot.offer) do offer[k] = v end
      offer.price = r.price
      if r.hidden then
        offer.faults = { table.unpack(offer.faults or {}) }
        offer.faults[#offer.faults + 1] = r.hidden.fault
        offer.foundFault = { key = r.hidden.key, cost = r.hidden.cost }
      end
      dealerRules.place(s, offer, 'auction', 0, now(s))
      toast(string.format(strings.t('carauction.sold_to_you'), name, r.price))
      extensions.hook('onStreetLegalChanged')
    else
      require('sl/core/state').addRep(s, -5)
      toast(string.format(strings.t('carauction.you_won_the_s_but'), name))
    end
  elseif r.sold == 'reserve' then
    toast(string.format(strings.t('carauction.the_reserve_on_the_s'), name))
  elseif r.sold == 'ai' then
    toast(string.format(strings.t('carauction.the_s_went_to_another'), name, r.price))
  end
end

local function tickYard(dt)
  local s = career()
  if not (s and yard) then return end
  yard.pushT = yard.pushT + dt
  local y = liveLot()
  if y then
    if yard.gap > 0 then
      yard.gap = yard.gap - dt
    elseif y.open then
      rules.step(y, dt, yard.rng)
      if not y.open then settleLive(s, y) yard.gap = YARD.gap yard.idx = yard.idx + 1 end
    end
  else
    state(s).yardDone = yard.day      -- the last lot has gone
    yard = nil
    M.list()
    return
  end
  if yard and yard.pushT >= 0.5 then yard.pushT = 0 M.list() end
end

-- a won car arrives (sl/dealers builds it from the order): the mechanic's finding comes in a text
function M.onStreetLegalCarDelivered(offer)
  if offer and offer.foundFault then
    sl_career.sendText('benny', string.format(strings.t('carauction.the_mechanic_found_s'), carName(offer), strings.t('carauction.fault_' .. offer.foundFault.key), offer.foundFault.cost), 2)
  end
end

local timer, failed = 0, false
function M.onUpdate(dtReal)
  if yard then local okY, errY = pcall(tickYard, dtReal or 0) if not okY and not failed then failed = true log('E', 'sl_carauctions', 'yard tick failed: ' .. tostring(errY)) yard = nil end end
  timer = timer + (dtReal or 0)
  if timer < 5 then return end
  timer = 0
  local s = career()
  if not s then return end
  local ok, err = pcall(function() tick(s) if viewing then M.list() end end)
  if not ok and not failed then failed = true log('E', 'sl_carauctions', 'tick failed: ' .. tostring(err)) end      -- (once: a failing tick must not fill the log)
end

return M
