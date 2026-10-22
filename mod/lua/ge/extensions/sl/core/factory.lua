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
      m.trims[#m.trims + 1] = { config = c.config, name = c.name, value = c.value, raw = c.raw }
    end
  end
  for _, m in ipairs(list) do
    table.sort(m.trims, function(a, b) if a.value ~= b.value then return a.value < b.value end return tostring(a.config) < tostring(b.config) end)
  end
  table.sort(list, function(a, b) if a.trims[1].value ~= b.trims[1].value then return a.trims[1].value < b.trims[1].value end return a.model < b.model end)
  return list
end

-- the dealer's own models, then the "Special order" group (the silly models no lot sells: carBuilder.specialOrder()), marked special = true
function M.withSpecial(pool, special)
  local list = M.catalogue(pool)
  for _, m in ipairs(M.catalogue(special)) do m.special = true list[#list + 1] = m end
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

-- an order whose car cannot be built (its model is gone, a mod was removed) must not keep the money for ever: tried every 5 s while the player is slow, so 60 failures are minutes of trying; then the order is
-- cancelled and its price comes back. Returns false while there are tries left; true and the amount when it is cancelled
M.MAX_BUILD_TRIES = 60
function M.buildFailed(orders, order)
  order.tries = (tonumber(order.tries) or 0) + 1
  if order.tries < M.MAX_BUILD_TRIES then return false end
  for i, o in ipairs(orders or {}) do if o == order then table.remove(orders, i) break end end
  return true, math.max(0, math.floor(tonumber(order.price) or 0))
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

-- C4 configurator: which group of the screen a slot belongs to, from its name, its own description and its option names; nil = not an option
-- a buyer would call one (lettering, taillight panels, sensors, ECUs, mounts ...): hidden. Only the visible, felt choices are kept.
M.GROUPS = { 'interior', 'wheels', 'steering', 'mudflaps', 'body', 'engine' }
local WORDS = { { 'mudflap', 'mudflaps' }, { 'steering', 'steering' }, { 'wheel', 'wheels' }, { 'tire', 'wheels' }, { 'rim', 'wheels' }, { 'hubcap', 'wheels' },
  { 'interior', 'interior' }, { 'seat', 'interior' }, { 'upholst', 'interior' }, { 'dashboard', 'interior' },
  { 'bumper', 'body' }, { 'spoiler', 'body' }, { 'wing', 'body' }, { 'hood', 'body' }, { 'roof', 'body' }, { 'skirt', 'body' }, { 'diffuser', 'body' }, { 'grille', 'body' },
  { 'engine', 'engine' }, { 'motor', 'engine' } }
local DENY = { 'lettering', 'panel', 'ecu', 'internals', 'mount', 'flywheel', 'sensor', 'cooling', 'intake', 'light', 'badge', 'plate', 'bar', 'gauge', 'mirror' }
function M.groupOf(slotText, optionText)
  local slot = tostring(slotText):lower()
  for _, d in ipairs(DENY) do
    if slot:find(d, 1, true) and not (d == 'bar' and (slot:find('steering', 1, true) or slot:find('bumper', 1, true))) then return nil end
  end
  local name = slot .. ' ' .. tostring(optionText or ''):lower()
  for _, w in ipairs(WORDS) do if name:find(w[1], 1, true) then return w[2] end end
  return nil
end

-- the factory options of the slots: configs = the parts maps (slot -> part) of the model's factory configs; a slot is an option when the
-- configs use more than one part in it (or the part is missing in some and present in others). Returns { slot -> sorted list of parts }
-- ('' = none fitted, left out of the list: only fitted parts are options).
function M.optionsOf(configs)
  local seen, out = {}, {}
  for _, parts in ipairs(configs or {}) do
    for slot, part in pairs(parts) do
      if type(part) == 'string' and part ~= '' then
        seen[slot] = seen[slot] or {}
        seen[slot][part] = true
      end
    end
  end
  for slot, set in pairs(seen) do
    local list = {}
    for part in pairs(set) do list[#list + 1] = part end
    table.sort(list)
    local missing = false
    for _, parts in ipairs(configs) do if (parts[slot] or '') == '' then missing = true end end
    if #list > 1 or (missing and #list == 1) then out[slot] = list end
  end
  return out
end

-- a game paint colour { r, g, b, a } (0..1 or 0..255; the alpha of a paint is its shine, not see-through) as a CSS colour
function M.css(c)
  if type(c) ~= 'table' then return 'rgb(128,128,128)' end
  local r, g, b = tonumber(c[1]) or 0, tonumber(c[2]) or 0, tonumber(c[3]) or 0
  local k = (r > 1.5 or g > 1.5 or b > 1.5) and 1 or 255
  local function f(x) return math.max(0, math.min(255, math.floor(x * k + 0.5))) end
  return string.format('rgb(%d,%d,%d)', f(r), f(g), f(b))
end

-- the total: the trim's price plus the price of each pick over the part it replaces
function M.total(trimValue, deltas)
  local sum = trimValue
  for _, d in pairs(deltas or {}) do sum = sum + (tonumber(d) or 0) end
  return sum
end

return M
