-- Street Legal: the tier of a lot (#22): high-end, mid-range, low-end or junk, from the median price of the cars it can offer. Pure,
-- tested by tools/luatest.js. The pool's median VALUE is turned into a median PRICE by the kind of lot (a dealer sells at value, the used
-- lot at about half, the scrap yard for scrap), so the same cut-offs work for all of them.

local M = {}

M.TIERS = {
  { id = 'high', label = 'High-end', min = 30000 },
  { id = 'mid', label = 'Mid-range', min = 12000 },
  { id = 'low', label = 'Low-end', min = 4000 },
  { id = 'junk', label = 'Junk', min = 0 },
}
M.FACTOR = { dealer = 1, used = 0.55, scrap = 0.05 }

function M.median(values)
  local v = {}
  for _, x in ipairs(values or {}) do if tonumber(x) then v[#v + 1] = tonumber(x) end end
  if #v == 0 then return nil end
  table.sort(v)
  local n = #v
  return n % 2 == 1 and v[(n + 1) / 2] or (v[n / 2] + v[n / 2 + 1]) / 2
end

-- the tier of a median price: id, label
function M.ofPrice(price)
  for _, t in ipairs(M.TIERS) do if (price or 0) >= t.min then return t.id, t.label end end
  return 'junk', 'Junk'
end

-- the tier of a lot of this kind ('dealer' | 'used' | 'scrap') selling cars of these values: id, label, median price; nil with no cars
function M.forPool(values, kind)
  local m = M.median(values)
  if not m then return nil end
  local price = m * (M.FACTOR[kind] or 1)
  local id, label = M.ofPrice(price)
  return id, label, price
end

-- The cars a lot of this tier may show (A2: a high-end dealer showed many cheap cars, drawn from its whole pool): those whose price lies from
-- 0.6 x the tier's floor up to 1.6 x the floor of the tier above (a junkyard has no premium cars, a high-end dealer no cheap ones). With fewer
-- than `need` cars left the pool is kept as it is: a lot is never empty because of its tier.
M.NEED = 6
function M.within(cars, tierId, kind, need)
  local at
  for i, t in ipairs(M.TIERS) do if t.id == tierId then at = i end end
  if not at then return cars end
  local f = M.FACTOR[kind] or 1
  local lo = M.TIERS[at].min * 0.6
  local hi = at > 1 and M.TIERS[at - 1].min * 1.6 or math.huge
  local out = {}
  for _, c in ipairs(cars or {}) do
    local price = (tonumber(c.value) or 0) * f
    if price >= lo and price <= hi then out[#out + 1] = c end
  end
  return #out >= (need or M.NEED) and out or cars
end

return M
