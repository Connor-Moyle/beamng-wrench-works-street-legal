-- Street Legal: factory orders at dealers (docs/FACTORY_ORDER.md). Pure: the catalogue of a dealer's pool and the order records.

local M = {}

M.DELIVERY_HOURS = 6                -- game hours from the order to the car on the garage forecourt

-- the pool (carBuilder.configs() entries: { model, config, name, brand, value }) as models with their trims, the cheapest model first
-- and each model's trims by price: { { model, brand, trims = { { config, name, value } } } }
function M.catalogue(pool)
  local byModel, list = {}, {}
  for _, c in ipairs(pool or {}) do
    if c.model and c.config then
      local m = byModel[c.model]
      if not m then
        m = { model = c.model, brand = c.brand or '', trims = {} }
        byModel[c.model], list[#list + 1] = m, m
      end
      m.trims[#m.trims + 1] = { config = c.config, name = c.name, value = c.value }
    end
  end
  for _, m in ipairs(list) do
    table.sort(m.trims, function(a, b) if a.value ~= b.value then return a.value < b.value end return tostring(a.config) < tostring(b.config) end)
  end
  table.sort(list, function(a, b) if a.trims[1].value ~= b.trims[1].value then return a.trims[1].value < b.trims[1].value end return a.model < b.model end)
  return list
end

-- the order record kept in the save; the price is the config's value, nothing added
function M.order(model, trim, paint, now)
  return { model = model, config = trim.config, name = trim.name, price = trim.value, paint = paint, due = now + M.DELIVERY_HOURS }
end

-- the first order that has arrived by hour `now` (index), or nil
function M.nextDue(orders, now)
  for i, o in ipairs(orders or {}) do
    if now >= o.due then return i end
  end
end

-- the saved paints list of a car with the chosen paint as its first (body) paint; the others are the config's own
function M.withPaint(paints, paint)
  local out = {}
  for i, p in ipairs(paints or {}) do out[i] = p end
  if paint then out[1] = paint end
  return out
end

-- when an order arrives: game day and hour
function M.arrives(o) return math.floor(o.due / 24), o.due % 24 end

return M
