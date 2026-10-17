-- Street Legal: car auctions (SLRR style). Pure rules, no game calls; tested by tools/luatest.js.
-- A lot is a car offer (sl/core/market's car offers: model, condition, faults, value) with a grade, a reserve price that stays hidden (the screen only says
-- whether it is met), maybe a fault the car report misses, and AI bidders with a budget and a manner: steady, early (opens high, then stops), sniper (the last seconds).
-- Time in a lot is seconds on the lot's own clock (`t`); the extension decides how fast that runs (live: real time at the yard, 1 s = 1 game minute online).
-- The rule that keeps it honest is listings': what an AI pays YOU for a car is under the least it can be bought for (listings.resaleCap).

local listings = require('sl/core/listings')

local M = {}

M.DURATION = 75            -- s a live lot is open
M.SOFT_CLOSE = 5           -- a bid in the last SOFT_CLOSE s adds SOFT_CLOSE s ...
M.SOFT_MAX = 3             -- ... at most this many times
M.SNIPE_AT = 8             -- s before the close the sniper bids
M.RESERVE = { 0.65, 0.95 } -- of the lot's fair worth
M.OPEN = 0.4               -- the opening bid, of fair worth
M.WATCH_WARNING = 10 / 60  -- game hours before a watched lot closes: the phone says so (10 game minutes)
M.SELL_FEE = listings.LISTING_FEE

-- condition 0..1 -> A..E
local CUTS = { { 0.85, 'A' }, { 0.70, 'B' }, { 0.50, 'C' }, { 0.30, 'D' } }
function M.grade(condition)
  for _, c in ipairs(CUTS) do if (condition or 0) >= c[1] then return c[2] end end
  return 'E'
end

-- a fault the report can miss, by grade: the chance a lot has one
local HIDDEN_CHANCE = { A = 0.03, B = 0.05, C = 0.08, D = 0.10, E = 0.12 }
-- what it is (market's fault id, the report's word, the repair as a share of the car's value); a tired clutch or a weeping head gasket is not on a report
M.HIDDEN = {
  { fault = 'gearbox', key = 'worn_clutch', share = 0.05 },
  { fault = 'gearbox', key = 'slipping_gearbox', share = 0.09 },
  { fault = 'engine', key = 'weeping_head_gasket', share = 0.12 },
  { fault = 'engine', key = 'tired_valve_seals', share = 0.07 },
  { fault = 'brakes', key = 'seized_caliper', share = 0.03 },
}

local function round(x, step) step = step or 10 return math.floor(x / step + 0.5) * step end

function M.increment(bid) return math.max(10, round((bid or 0) * 0.05)) end

local STYLES = { 'steady', 'steady', 'early', 'sniper' }

-- the bidders of a lot: budgets are shares of the car's fair worth. cap: the most a bidder may reach (nil = 1.1 x fair)
function M.bidders(rng, fair, cap)
  local list = {}
  for i = 1, rng:int(3, 5) do
    local budget = fair * rng:range(0.55, 1.1)
    if cap then budget = math.min(budget, cap) end
    list[i] = { id = i, style = STYLES[rng:int(#STYLES)], budget = round(budget), moved = 0, nextAt = rng:range(1, 5) }
  end
  return list
end

-- a lot for an offer (market.lua's car offer). hour: career hours when it opens; closes: absolute career hour (online) or nil for a live lot
function M.newLot(rng, offer, hour, closes)
  local condition = offer.condition or 0.6
  local duration = closes and math.max(M.DURATION, (closes - (hour or 0)) * 60) or M.DURATION      -- (online: the lot clock is game minutes)
  local fair = listings.fair(offer.value, condition)
  local grade = M.grade(condition)
  local lot = { offer = offer, condition = condition, grade = grade, fair = fair, bid = 0, high = nil, bids = 0,
    reserve = round(fair * rng:range(M.RESERVE[1], M.RESERVE[2])), opening = math.max(10, round(fair * M.OPEN)),
    t = 0, closesAt = duration, duration = duration, pace = duration / M.DURATION, extended = 0, open = true, opened = hour or 0, closes = closes }
  if rng:float() < HIDDEN_CHANCE[grade] then
    local h = M.HIDDEN[rng:int(#M.HIDDEN)]
    lot.hidden = { fault = h.fault, key = h.key, cost = round(math.max(60, (offer.value or 0) * h.share), 10) }
  end
  lot.bidders = M.bidders(rng, fair)
  for _, b in ipairs(lot.bidders) do b.nextAt = b.nextAt * lot.pace end
  return lot
end

function M.reserveMet(lot) return lot.bid >= lot.reserve end
function M.nextMin(lot) return lot.bid == 0 and lot.opening or lot.bid + M.increment(lot.bid) end
function M.remaining(lot) return math.max(0, lot.closesAt - lot.t) end

-- a bid at lot time t: soft close (a bid in the last seconds adds time, a few times)
local function place(lot, who, amount)
  lot.bid, lot.high, lot.bids = amount, who, lot.bids + 1
  if M.remaining(lot) <= M.SOFT_CLOSE and lot.extended < M.SOFT_MAX then
    lot.extended = lot.extended + 1
    lot.closesAt = lot.closesAt + M.SOFT_CLOSE
  end
end

-- you bid: false, reason ('closed' | 'low' | 'cash' | 'yours' = you are already the highest)
function M.youBid(lot, amount, cash)
  if not lot.open then return false, 'closed' end
  if lot.high == 'you' then return false, 'yours' end
  if amount < M.nextMin(lot) then return false, 'low' end
  if (cash or 0) < amount then return false, 'cash' end
  place(lot, 'you', amount)
  return true
end

-- the AI bidders for dt seconds of the lot clock; returns the bids made { {bidder, amount, t}, ... }; ends the lot when the clock passes closesAt
function M.step(lot, dt, rng)
  local made = {}
  if not lot.open then return made end
  lot.t = lot.t + dt
  for _, b in ipairs(lot.bidders) do
    if lot.high ~= b.id and lot.open then
      local left = M.remaining(lot)
      local want
      if b.style == 'steady' then
        if lot.t >= b.nextAt then
          b.nextAt = lot.t + rng:range(2, 6) * lot.pace
          if rng:float() < 0.6 then want = lot.bid == 0 and lot.opening or lot.bid + M.increment(lot.bid) end
        end
      elseif b.style == 'early' then
        if b.moved < 2 and lot.t < lot.duration * 0.3 and lot.t >= b.nextAt then
          b.nextAt = lot.t + rng:range(3, 8) * lot.pace
          local jump = math.max(lot.opening, round((lot.bid == 0 and lot.opening or lot.bid) * 1.25))
          want = math.min(jump, round(b.budget * 0.7))
          if want < M.nextMin(lot) then want = nil end
        end
      else      -- sniper: one bid, late
        if left <= M.SNIPE_AT and b.moved == 0 then
          want = math.min(round(b.budget), math.max(M.nextMin(lot), round((lot.bid == 0 and lot.opening or lot.bid) * 1.12)))
        end
      end
      if want and want >= M.nextMin(lot) and want <= b.budget then
        b.moved = b.moved + 1
        place(lot, b.id, want)
        made[#made + 1] = { bidder = b.id, amount = want, t = lot.t }
      end
    end
  end
  if lot.t >= lot.closesAt then lot.open = false end
  return made
end

-- runs a lot to its end at once (the online auctions between visits); returns the bids made
function M.finish(lot, rng, tick)
  local all = {}
  tick = tick or lot.pace or 1
  local guard = 0
  while lot.open and guard < 2000 do
    guard = guard + 1
    for _, b in ipairs(M.step(lot, tick, rng)) do all[#all + 1] = b end
  end
  return all
end

-- the result of a closed lot: sold ('you' | 'ai' | 'none' | 'reserve'), price. A lot under its reserve does not sell
function M.result(lot)
  if lot.open then return nil end
  if lot.bid <= 0 then return { sold = 'none', price = 0 } end
  if lot.bid < lot.reserve then return { sold = 'reserve', price = lot.bid } end
  return { sold = lot.high == 'you' and 'you' or 'ai', price = lot.bid, hidden = lot.high == 'you' and lot.hidden or nil }
end

-- the delivery fee for a car won online (picked up at the yard: none)
function M.delivery(price) return listings.delivery(price) end

-- ONE OF YOUR CARS at auction. car: { value, condition }, reserve: what you set (nil = 80 % of fair worth). The AI bidders stay under what a buyer would pay
-- for it (listings.resaleCap), so a car bought at auction and sold again never makes money
function M.sellLot(rng, car, reserve, hour, closes)
  local condition = car.condition or 0.6
  local duration = closes and math.max(M.DURATION, (closes - (hour or 0)) * 60) or M.DURATION
  local fair = listings.fair(car.value, condition)
  local cap = listings.resaleCap(car.value, condition)
  local lot = { offer = car, condition = condition, grade = M.grade(condition), fair = fair, bid = 0, bids = 0, mine = true,
    reserve = reserve and round(reserve) or round(fair * 0.8), opening = math.max(10, round(cap * 0.3)),
    t = 0, closesAt = duration, duration = duration, pace = duration / M.DURATION, extended = 0, open = true, opened = hour or 0, closes = closes }
  lot.bidders = M.bidders(rng, fair, cap)
  for _, b in ipairs(lot.bidders) do b.nextAt = b.nextAt * lot.pace end
  return lot
end

-- what reaches you when your lot sells (after the fee), or nil when it did not
function M.sellProceeds(lot)
  local r = M.result(lot)
  if not r or r.sold ~= 'ai' and r.sold ~= 'you' then return nil end
  return listings.proceeds(r.price)
end

-- the lot's grade and report line for the screen: the visible faults only; a hidden one is never in this list
function M.reportFaults(lot)
  return lot.offer.faults or {}
end

-- watch list: the lots (of a list with .closes in career hours) a watcher should hear about now: closing within WATCH_WARNING and not told yet
function M.watchDue(lots, nowHour)
  local out = {}
  for _, l in ipairs(lots) do
    if l.watched and not l.told and l.closes and l.closes - nowHour <= M.WATCH_WARNING and l.closes > nowHour then out[#out + 1] = l end
  end
  return out
end

return M
