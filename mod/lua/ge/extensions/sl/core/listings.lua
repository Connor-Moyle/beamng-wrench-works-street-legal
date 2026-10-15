-- Street Legal: the used parts and cars market (Design 4, X12) - the Valo Classifieds paper, the Revline app and
-- Swap & Bid auctions share these rules. No game calls: items are { kind = 'part'|'car', name, value (BeamNG's
-- new value), section }, rng is sl/core/rng, hours are career hours (day * 24 + hour).
--
-- The one rule that keeps it honest: whatever a buyer (an AI buyer or a bidder) pays you for something is
-- under the least it can be bought for in any channel (M.MIN_BUY), and a market part goes on the Wrench Works
-- shelf valued at what was paid (the counter pays half of that). So buying and selling again always loses.

local M = {}

local function round(x, step) step = step or 10 return math.floor(x / step + 0.5) * step end
local function up(x) return math.ceil(x / 10 - 1e-9) * 10 end      -- sellers round their prices up

-- used worth of a thing by its condition (0..1): what everything else is a share of
function M.fair(value, condition) return (value or 0) * (0.35 + 0.65 * (condition or 0.5)) end   -- (as new: its full value)

-- the condition of one of your shelf parts (Wrench Works' shelfItems): its wear if it came from the market, else
-- nearly new, and a bent one at most half
function M.condition(item)
  local c = item.wear and (1 - item.wear) or 0.9
  if item.damaged then c = math.min(c, 0.5) end
  return math.max(0.05, math.min(1, c))
end

-- channels: the asking price as a share of fair worth, and how long a listing lasts (hours)
M.CHANNELS = { paper = { ask = 0.85, life = 24 }, app = { ask = 1.0, life = 72 }, auction = { ask = 0.65, life = 36 } }
M.DEMAND = { 0.9, 1.1 }                -- a section's demand this week (low, high)
M.MOODS = { eager = { ask = 0.95, floor = 0.85 }, normal = { ask = 1.0, floor = 0.9 }, firm = { ask = 1.05, floor = 0.95 } }
M.MOOD_LIST = { 'eager', 'normal', 'normal', 'firm' }
M.PAPER_PRICE = 2
M.LISTING_FEE = 0.05                   -- of the sale, when one of your listings sells
M.DEPOSIT = 0.1                        -- of the price, paid on agreeing a pickup
M.DELIVERY = { base = 40, share = 0.06 }
M.RARE = 0.03                          -- of listings: nearly new (the game picks a rare item for these: a performance part, a rare car)
M.SCAM = 0.03                          -- of app listings
M.SHADY = 0.15                         -- of sellers: a low rating; half of them don't turn up
M.NEW_ACCOUNT = 0.1                    -- of honest sellers have a new account too (so it's a hint, not proof)

-- the least anything can be bought for, as a share of its fair worth, over every channel, mood and demand
-- (auctions: the opening bid, nobody else bidding)
do
  local low = math.huge
  for name, c in pairs(M.CHANNELS) do
    local share = c.ask * M.DEMAND[1]
    if name ~= 'auction' then
      for _, m in pairs(M.MOODS) do low = math.min(low, share * m.ask * m.floor) end
    else
      low = math.min(low, share)
    end
  end
  M.MIN_BUY = low
end
M.RESALE = 0.95                        -- buyers pay at most this share of the least it could be bought for

-- the most any buyer pays you for a thing of this worth and condition
function M.resaleCap(value, condition) return M.fair(value, condition) * M.MIN_BUY * M.RESALE end

-- a section's demand for the week
function M.demand(rng) return rng:range(M.DEMAND[1], M.DEMAND[2]) end

-- a new listing for item in channel. Scams: far too cheap, a brand-new account and "deposit by transfer only"
-- (all three, every time - the tells). No-shows: only sellers with a low rating
function M.listing(rng, item, channel, demand, hour)
  local c = M.CHANNELS[channel]
  local rare = rng:float() < M.RARE
  local condition = item.condition or (rare and rng:range(0.85, 1.0) or rng:range(0.15, 0.95))   -- (a car: its own)
  local mood = M.MOOD_LIST[rng:int(#M.MOOD_LIST)]
  local fair = M.fair(item.value, condition)
  local ask = fair * c.ask * (demand or 1)
  if channel ~= 'auction' then ask = ask * M.MOODS[mood].ask end
  local l = { kind = item.kind, item = item, channel = channel, condition = condition, wear = 1 - condition, rare = rare,
    mood = mood, posted = hour or 0, expires = (hour or 0) + c.life, rating = rng:int(3, 5), newAccount = rng:float() < M.NEW_ACCOUNT }
  if channel == 'app' and rng:float() < M.SCAM then
    l.scam, l.newAccount, l.payNote, l.rating = true, true, 'deposit by transfer only', rng:int(1, 2)
    ask = fair * 0.4
  elseif rng:float() < M.SHADY then
    l.rating = rng:int(1, 2)
    l.noShow = rng:float() < 0.5
  end
  l.ask = math.max(10, up(ask))
  l.floor = channel == 'auction' and l.ask or math.max(10, up(l.ask * M.MOODS[mood].floor))
  return l
end

-- the tells a careful buyer can read off a listing (for the UI: "too cheap", "new account", "transfer only")
function M.tells(l)
  local t = {}
  if l.ask < M.fair(l.item.value, l.condition) * M.MIN_BUY then t[#t + 1] = 'price far below what it is worth' end
  if l.newAccount then t[#t + 1] = 'new account' end
  if l.payNote then t[#t + 1] = l.payNote end
  if (l.rating or 5) <= 2 then t[#t + 1] = 'poor seller rating' end
  return t
end

-- haggling with a seller: 'accept', price | 'counter', price | 'decline' | 'walk' (round: offers made so far)
function M.haggle(l, offer, round_)
  offer = tonumber(offer) or 0
  if offer >= l.ask then return 'accept', l.ask end
  if offer >= l.floor then return 'accept', round(offer) end
  if (round_ or 0) >= 2 then return 'walk' end
  if offer >= l.floor * 0.8 then return 'counter', math.max(l.floor, up((offer + l.ask) / 2)) end
  return 'decline'
end

-- an AI buyer's offer for one of your listings (lowballers included); never above the resale cap
function M.buyerOffer(rng, value, condition) return M.offerUpTo(rng, M.resaleCap(value, condition)) end

-- an AI buyer's offer up to a cap (lowballers included)
function M.offerUpTo(rng, cap)
  local share = rng:float() < 0.3 and rng:range(0.4, 0.6) or rng:range(0.7, 1.0)
  return math.max(10, math.floor(cap * share / 10) * 10)
end

-- auctions: the AI bidders' next bid on a lot (nil when none of them goes higher). max: what the bidders are
-- worth paying (for your own lots, the resale cap)
function M.nextBid(rng, current, max)
  local step = math.max(10, round(current * 0.05))
  if current + step > max or rng:float() < 0.35 then return nil end
  return current + step
end

-- what a pickup deposit and a delivery cost
function M.deposit(price) return math.max(10, round(price * M.DEPOSIT)) end
function M.delivery(price) return round(M.DELIVERY.base + price * M.DELIVERY.share) end

-- you sell: what reaches you after the fee
function M.proceeds(price) return math.floor(price * (1 - M.LISTING_FEE)) end

function M.canList(item) return type(item) == 'table' and not item.foreign end

return M
