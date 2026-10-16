-- Street Legal: buying from the stock dealers on the laptop (docs/LAPTOP_DESIGN.md L3). Pure rules, no game calls.
-- The offers are the lot's (sl_lot.offersFor); a purchase marks the offer bought (so the lot never shows it again) and
-- puts an order in the career save (s.orders: plain data, it saves and loads with the rest); the car is built and
-- delivered to the garage when the order is due.
local M = {}

local rngLib = require('sl/core/rng')

M.MIN_HOURS, M.MAX_HOURS, M.METRES_PER_HOUR = 2, 6, 3000

-- game hours since the start: the day changes at 06:00 (sl_career), so the clock counts from then
function M.clock(day, hour) return (day or 1) * 24 + ((hour or 0) - 6) % 24 end

-- the year of a listed car, as the stock shop gives one: somewhere in the config's years (aggregates.Years { min, max }), the same
-- for the same offer every time
function M.yearOf(id, years)
  local lo, hi = 2000, 2023
  if type(years) == 'table' then lo, hi = tonumber(years.min) or lo, tonumber(years.max) or hi
  elseif tonumber(years) then lo = tonumber(years) hi = lo end
  if hi < lo then hi = lo end
  return lo + rngLib.hash(tostring(id)) % (hi - lo + 1)
end

-- what a stock listing shows of a car, from the game's config entry (core_vehicles.getConfigList): nil where the config has none
function M.specs(raw)
  raw = type(raw) == 'table' and raw or {}
  local function str(v) return type(v) == 'string' and v ~= '' and v or nil end
  return { power = tonumber(raw.Power), weight = tonumber(raw.Weight), drivetrain = str(raw.Drivetrain), transmission = str(raw.Transmission),
    fuel = str(raw['Fuel Type']), body = str(raw['Body Style']), topSpeed = tonumber(raw['Top Speed']) }
end

-- 2 to 6 hours, by the distance from the dealer to the garage
function M.delayHours(metres)
  return math.max(M.MIN_HOURS, math.min(M.MAX_HOURS, M.MIN_HOURS + math.floor((tonumber(metres) or 0) / M.METRES_PER_HOUR)))
end

function M.ordered(s, offerId)
  for _, o in ipairs(s.orders or {}) do if o.offer.id == offerId then return true end end
  return false
end

-- can this offer be bought now? -> ok, reason
function M.canBuy(s, offer)
  if not offer then return false, 'That car has gone.' end
  if (s.bought or {})[offer.id] or M.ordered(s, offer.id) then return false, 'That car has gone.' end
  if s.money < offer.price then return false, string.format('It is $%d. You have $%d.', offer.price, s.money) end
  return true
end

-- the order, once the money is taken: the offer is marked bought and the car is due after the delay
function M.place(s, offer, placeId, metres, now)
  s.bought = s.bought or {}
  s.bought[offer.id] = true
  s.orders = s.orders or {}
  local hours = M.delayHours(metres)
  local order = { offer = offer, place = placeId, ordered = now, due = now + hours, hours = hours }
  s.orders[#s.orders + 1] = order
  return order
end

-- a private seller's car (Revline) bought for delivery: the same order as a dealer's, its id the listing's
function M.orderPrivate(s, listing, price, yard, now)
  local offer = {}
  for k, v in pairs(listing.offer) do offer[k] = v end
  offer.id, offer.price = 'revline:' .. listing.id, price
  local metres = math.sqrt((listing.where.x - yard.x) ^ 2 + (listing.where.y - yard.y) ^ 2)
  return M.place(s, offer, 'revline', metres, now)
end

-- the first order that is due (one is delivered at a time)
function M.nextDue(s, now)
  for _, o in ipairs(s.orders or {}) do if o.due <= now + 0.05 then return o end end      -- (three minutes of slack: the clock is read back from the sky's float)
end

function M.remove(s, order)
  for i, o in ipairs(s.orders or {}) do if o == order then table.remove(s.orders, i) return true end end
  return false
end

return M
