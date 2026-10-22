-- Street Legal: the weekly costs (career expansion #1). Every 7th day the garage you hold and the cars you keep are billed; what the player cannot cover goes to a debt
-- (never a repossession), which a later week with spare money pays off first. Pure, no game calls: tested by tools/luatest.js, tuned with tools/economy_sim.py.
-- The bank's own weekly items (the loan quarter, the insurance premium) stay in core/bank; the ledger shows them next to these.

local M = {}

local strings = require('sl/core/strings')

M.DAYS = 7
M.RENT = { [1] = 0, [2] = 150, [3] = 400 }       -- a week of the garage you hold (the first one is the starter lock-up)
M.FREE_CARS = 2                                   -- cars kept free of charge
M.STORAGE = 40                                    -- a week for each car beyond those
M.BUFFER = 200                                    -- debt is paid down only from money above this
M.MISS_REP = -5                                   -- a week with a bill left unpaid
M.KEEP = 8                                        -- weeks of history

function M.week(day) return math.floor(((tonumber(day) or 1) - 1) / M.DAYS) + 1 end
function M.dayOfWeek(day) return ((tonumber(day) or 1) - 1) % M.DAYS + 1 end

-- the bill lines for a week: { { id, label, amount } }
function M.lines(garageLevel, carCount, rentScale, storage)
  local out = {}
  local rent = math.floor((M.RENT[garageLevel or 1] or M.RENT[3]) * (tonumber(rentScale) or 1) + 0.5)
  if rent > 0 then out[#out + 1] = { id = 'rent', label = strings.t('weekly.rent'), amount = rent } end
  local extra = math.max(0, (carCount or 0) - M.FREE_CARS)
  if extra > 0 and (tonumber(storage) or M.STORAGE) > 0 then out[#out + 1] = { id = 'storage', label = strings.t('weekly.storage', extra), amount = extra * (tonumber(storage) or M.STORAGE) } end
  return out
end

function M.total(lines)
  local t = 0
  for _, l in ipairs(lines) do t = t + l.amount end
  return t
end

-- money in hand, the debt carried, the bills: what leaves the wallet and the debt after. pay = bills paid + debt repaid, short = bills not covered (they join the debt)
function M.settle(money, debt, owe)
  money, debt = math.max(0, money or 0), math.max(0, debt or 0)
  local billsPaid = math.min(money, owe)
  local repaid = math.min(math.max(0, money - billsPaid - M.BUFFER), debt)
  local short = owe - billsPaid
  return { pay = billsPaid + repaid, billsPaid = billsPaid, repaid = repaid, short = short, debt = debt - repaid + short }
end

function M.newState(day) return { nextDue = (day or 1) + M.DAYS, debt = 0, history = {} } end

-- the week's entry in the history (newest first)
function M.record(w, entry)
  table.insert(w.history, 1, entry)
  while #w.history > M.KEEP do table.remove(w.history) end
end

return M
