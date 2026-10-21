-- Street Legal: the shops (rules of sl/shops; docs/MODDING_SHOPS.md). Pure, no game calls: tested by tools/luatest.js.
-- A shop is a kind (its own themed screen), a name and where its goods come from. Kinds are data (M.TYPES): another mod can add one with M.define. The screen
-- (ui/modModules/slShop) draws any shop from the record sl/shops sends it, so a new kind is a theme and a stock rule, not a new screen.
--   goods   'tyres'    the tyre ranges of sl/core/tyres (price from its quote)
--           'given'    the opener hands the list in (opts.stock): the map modder's own goods, or another mod's
--           'catalog'  parts for the player's car from the Wrench Works catalog (filled in by sl/shops, which asks Wrench Works; empty until it can)
--           'services' jobs with a price and no goods (paint, tuner, mechanic, wash)

local M = {}

local rng = require('sl/core/rng')
local tyres = require('sl/core/tyres')
local strings = require('sl/core/strings')

-- the kinds: theme = what the screen draws differently (accent colour, a header pattern, an icon); screen = which layout; sections = the Wrench Works catalog sub-chapters a
-- 'catalog' shop sells (slrr/garageCatalog ids); hours = the sl/core/hours kind
M.TYPES = {
  tyre =        { title = 'Tyre shop',          goods = 'tyres',    screen = 'catalogue', theme = { accent = '#f2b84b', pattern = 'tread',    icon = 'tyre' },     hours = 'shop' },
  exhaust =     { title = 'Exhaust shop',       goods = 'catalog',  screen = 'catalogue', theme = { accent = '#e9855b', pattern = 'pipes',    icon = 'exhaust' },  hours = 'shop', sections = { 'exhaust' } },
  parts =       { title = 'Parts shop',         goods = 'catalog',  screen = 'catalogue', theme = { accent = '#7cc4a6', pattern = 'grid',     icon = 'wrench' },   hours = 'shop' },
  performance = { title = 'Performance shop',   goods = 'catalog',  screen = 'catalogue', theme = { accent = '#d9575f', pattern = 'chevrons', icon = 'engine' },   hours = 'shop', sections = { 'intake', 'forced', 'internals', 'management', 'cooling', 'fuel' } },
  paint =       { title = 'Paint and body',     goods = 'services', screen = 'services',  theme = { accent = '#9b8cf0', pattern = 'spray',    icon = 'paint' },    hours = 'shop' },
  tuner =       { title = 'Tuner',              goods = 'services', screen = 'services',  theme = { accent = '#5fb7e6', pattern = 'dyno',     icon = 'gauge' },    hours = 'shop' },
  mechanic =    { title = 'Mechanic',           goods = 'services', screen = 'services',  theme = { accent = '#b0b8c4', pattern = 'bolts',    icon = 'spanner' },  hours = 'shop' },
  accessories = { title = 'Accessories',        goods = 'given',    screen = 'catalogue', theme = { accent = '#e86fb0', pattern = 'stripes',  icon = 'star' },     hours = 'shop' },
  dealerparts = { title = 'Dealer parts',       goods = 'catalog',  screen = 'catalogue', theme = { accent = '#8ab4f8', pattern = 'badge',    icon = 'badge' },    hours = 'dealer' },
}
M.ORDER = { 'tyre', 'exhaust', 'parts', 'performance', 'paint', 'tuner', 'mechanic', 'accessories', 'dealerparts' }
local KINDS = { 'catalogue', 'services' }

-- the wording of a kind: the string keys of its tagline (under the name when there is no keeper), the add and the pay buttons (sl/shops turns them into text)
M.WORDS = {
  tyre = { tag = 'shops.tag_tyre', add = 'shops.word_choose', buy = 'shops.word_fit' },
  exhaust = { tag = 'shops.tag_exhaust', add = 'shops.word_add', buy = 'shops.word_pay' },
  parts = { tag = 'shops.tag_parts', add = 'shops.word_add', buy = 'shops.word_pay' },
  performance = { tag = 'shops.tag_performance', add = 'shops.word_add', buy = 'shops.word_order' },
  paint = { tag = 'shops.tag_paint', add = 'shops.word_book', buy = 'shops.word_book_pay' },
  tuner = { tag = 'shops.tag_tuner', add = 'shops.word_book', buy = 'shops.word_book_pay' },
  mechanic = { tag = 'shops.tag_mechanic', add = 'shops.word_book', buy = 'shops.word_book_pay' },
  accessories = { tag = 'shops.tag_accessories', add = 'shops.word_add', buy = 'shops.word_pay' },
  dealerparts = { tag = 'shops.tag_dealerparts', add = 'shops.word_add', buy = 'shops.word_order' },
}

local GOODS = { tyres = true, given = true, catalog = true, services = true }

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function isHex(s) return type(s) == 'string' and s:match('^#%x%x%x%x%x%x$') ~= nil end

-- the optional extras of an item or a service: specs (label, text, bar 0..1: up to six rows in the detail pane), a colour swatch, a curve (up to 64 numbers) with its label
local function extras(it, out)
  if type(it.specs) == 'table' then
    out.specs = {}
    for _, sp in ipairs(it.specs) do
      if type(sp) == 'table' and sp.label and #out.specs < 6 then
        out.specs[#out.specs + 1] = { label = tostring(sp.label), text = sp.text ~= nil and tostring(sp.text) or nil, bar = tonumber(sp.bar) and clamp(tonumber(sp.bar), 0, 1) or nil }
      end
    end
  end
  if isHex(it.swatch) then out.swatch = it.swatch end
  if type(it.curve) == 'table' then
    out.curve = {}
    for _, v in ipairs(it.curve) do if tonumber(v) and #out.curve < 64 then out.curve[#out.curve + 1] = tonumber(v) end end
    if #out.curve < 2 then out.curve = nil else out.curveLabel = it.curveLabel and tostring(it.curveLabel) or nil end
  end
  return out
end

function M.type(kind) return M.TYPES[kind] end
function M.kinds()
  local out = {}
  for _, id in ipairs(M.ORDER) do out[#out + 1] = id end
  return out
end

-- another mod adds a kind: define(id, { title, goods, screen, theme = { accent, pattern, icon }, sections, hours }). Returns true, or false and the reason; a built-in kind cannot be replaced
function M.define(id, def)
  if type(id) ~= 'string' or not id:match('^[%a][%w_]*$') then return false, 'the id must be letters, digits and _' end
  if M.TYPES[id] and not M.TYPES[id].custom then return false, 'a built-in shop kind cannot be replaced' end
  if type(def) ~= 'table' or type(def.title) ~= 'string' or def.title == '' then return false, 'a title is needed' end
  if not GOODS[def.goods or 'given'] then return false, 'unknown goods: ' .. tostring(def.goods) end
  local screen = def.screen or 'catalogue'
  if screen ~= KINDS[1] and screen ~= KINDS[2] then return false, 'unknown screen: ' .. tostring(screen) end
  local th = def.theme or {}
  M.TYPES[id] = { title = def.title, goods = def.goods or 'given', screen = screen, hours = def.hours or 'shop', sections = def.sections, custom = true,
    theme = { accent = isHex(th.accent) and th.accent or '#a8c7fa', pattern = tostring(th.pattern or 'grid'), icon = tostring(th.icon or 'wrench') } }
  local known = false
  for _, k in ipairs(M.ORDER) do if k == id then known = true end end
  if not known then M.ORDER[#M.ORDER + 1] = id end
  return true
end

-- a shop record from what the opener passes (sl_shops.open) or a marker's fields: kind (needed), name, brand, hours = { open, close }, keeper, stock, services.
-- Returns the cleaned record, or nil and the reason
function M.normalize(kind, opts)
  local t = M.TYPES[kind]
  if not t then return nil, 'unknown shop kind: ' .. tostring(kind) end
  opts = type(opts) == 'table' and opts or {}
  local s = { kind = kind, title = t.title, name = tostring(opts.name or t.title), brand = opts.brand and tostring(opts.brand) or nil, goods = t.goods, screen = t.screen,
    theme = { accent = t.theme.accent, pattern = t.theme.pattern, icon = t.theme.icon }, hoursKind = t.hours, sections = t.sections, stock = {}, services = {} }
  if type(opts.theme) == 'table' then
    if isHex(opts.theme.accent) then s.theme.accent = opts.theme.accent end
    if opts.theme.pattern then s.theme.pattern = tostring(opts.theme.pattern) end
  end
  if type(opts.hours) == 'table' and tonumber(opts.hours[1]) and tonumber(opts.hours[2]) then
    s.hours = { clamp(tonumber(opts.hours[1]), 0, 24), clamp(tonumber(opts.hours[2]), 0, 24) }
  end
  if type(opts.keeper) == 'table' then s.keeper = { name = tostring(opts.keeper.name or ''), line = opts.keeper.line and tostring(opts.keeper.line) or nil } end
  for _, it in ipairs(type(opts.stock) == 'table' and opts.stock or {}) do
    if type(it) == 'table' and type(it.id) == 'string' and tonumber(it.price) and it.price >= 0 then
      s.stock[#s.stock + 1] = extras(it, { id = it.id, name = tostring(it.name or it.id), price = math.floor(it.price + 0.5), cond = it.cond and clamp(tonumber(it.cond) or 1, 0, 1) or nil,
        group = it.group and tostring(it.group) or nil, desc = it.desc and tostring(it.desc) or nil, count = it.count and math.max(1, math.floor(tonumber(it.count))) or nil })
    end
  end
  for _, sv in ipairs(type(opts.services) == 'table' and opts.services or {}) do
    if type(sv) == 'table' and type(sv.id) == 'string' and tonumber(sv.price) and sv.price >= 0 then
      s.services[#s.services + 1] = extras(sv, { id = sv.id, name = tostring(sv.name or sv.id), price = math.floor(sv.price + 0.5), minutes = math.max(0, math.floor(tonumber(sv.minutes) or 0)), desc = sv.desc and tostring(sv.desc) or nil })
    end
  end
  if t.goods == 'tyres' and #s.stock == 0 then s.stock = M.tyreStock(opts.range) end
  return s
end

-- a marker's fields (a level's shops file, a scene object's dynamic fields) as the opener's table: keys are matched without case, 'hours' is "8-18"
function M.fromMarker(fields)
  if type(fields) ~= 'table' then return nil, 'no fields' end
  local f = {}
  for k, v in pairs(fields) do f[tostring(k):lower()] = v end
  local kind = tostring(f.kind or f.shop or f.slshop or ''):lower()
  if not M.TYPES[kind] then return nil, 'unknown shop kind: ' .. kind end
  local o = { name = f.name, brand = f.brand, theme = { accent = f.accent } }
  if type(f.hours) == 'string' then
    local a, b = f.hours:match('^%s*(%d+)%s*%-%s*(%d+)%s*$')
    if a then o.hours = { tonumber(a), tonumber(b) } end
  elseif type(f.hours) == 'table' then o.hours = f.hours end
  if f.keeper then o.keeper = type(f.keeper) == 'table' and f.keeper or { name = tostring(f.keeper) } end
  o.stock, o.services, o.range = f.stock, f.services, f.range
  return kind, o
end

-- the facts of a tyre compound from Car Surface FX's rules (csfx_tyrerules.COMPOUNDS; dry grip 1.00 is a road tyre): dry grip, wet grip, tread, working temperature, loose ground. nil without the rules
function M.tyreSpecs(id, rules)
  local c = type(rules) == 'table' and type(rules.COMPOUNDS) == 'table' and rules.COMPOUNDS[id]
  if type(c) ~= 'table' or not c.base then return nil end
  local wet = (c.wet0 or 0.8) * (c.wetF or 1)
  local loose = c.loose or 1
  return {
    { label = strings.t('shops.spec_dry'), text = string.format('%.2f', c.base), bar = clamp((c.base - 0.8) / 0.5, 0, 1) },
    { label = strings.t('shops.spec_wet'), text = string.format('%.2f', wet), bar = clamp(wet / 1.2, 0, 1) },
    { label = strings.t('shops.spec_tread'), text = string.format('%.0f mm', c.h0 or 0), bar = clamp((c.h0 or 0) / 15, 0, 1) },
    { label = strings.t('shops.spec_temp'), text = string.format('%d to %d C', c.lo or 0, c.hi or 0) },
    { label = strings.t('shops.spec_loose'), text = string.format('%.2f', loose), bar = clamp(loose / 1.3, 0, 1) },
  }
end

-- the tyres of a range ('torres' or 'race'; nil: all) as stock: one line per compound, the price of a set
function M.tyreStock(range)
  local out = {}
  for _, id in ipairs(tyres.ORDER) do
    local c = tyres.COMPOUNDS[id]
    if range == nil or c.shop == range then out[#out + 1] = { id = id, name = tyres.name(id), price = c.set, group = c.family } end
  end
  return out
end

-- open now? hour = 0..24 (the engine's day fraction goes through sl/core/hours); a shop's own hours win over its kind's
function M.isOpen(shop, hour)
  if shop.hours then
    local a, b = shop.hours[1], shop.hours[2]
    return hour >= a and hour < b
  end
  return true
end

-- the price of an item for this player: base price, a reputation discount of 1% per title tier up to 8%, a used part's condition share, a shop's favour (0..1) up to 5%
function M.price(item, ctx)
  ctx = ctx or {}
  local base = item.price
  if item.cond and ctx.wearPriced then base = base * (0.35 + 0.65 * clamp(item.cond, 0, 1)) end
  local off = 0
  if ctx.repDiscount then off = off + clamp((ctx.tier or 0) * 0.01, 0, 0.08) end
  off = off + clamp((ctx.favour or 0) * 0.05, 0, 0.05)
  return math.max(0, math.floor(base * (1 - off) + 0.5))
end

-- the stock for a day: a seeded, repeatable pick of the shop's goods (a shop never stocks everything; shelves differ day to day and between shops). `keep` lines always stay
function M.dayStock(shop, day, keep)
  local r = rng.new((day or 1) * 7919 + #(shop.name or '') * 104729 + (shop.kind or ''):byte(1, 1) * 31)
  local out, kept = {}, keep or 4
  for i, it in ipairs(shop.stock) do
    if i <= kept or r:chance(0.75) then out[#out + 1] = it end
  end
  return out
end

-- a cart { { id, qty } } against the stock and the money: returns the lines with their prices and the total, or nil and the reason. Nothing is taken from here
function M.checkout(shop, cart, money, ctx)
  if type(cart) ~= 'table' or #cart == 0 then return nil, strings.t('shops.cart_empty') end
  local byId = {}
  for _, it in ipairs(shop.stock) do byId[it.id] = it end
  for _, sv in ipairs(shop.services) do byId[sv.id] = sv end
  local lines, total, at = {}, 0, {}
  for _, c in ipairs(cart) do
    local it = type(c) == 'table' and byId[c.id]
    if not it then return nil, strings.t('shops.not_in_stock') end
    local qty = math.max(1, math.floor(tonumber(c.qty) or 1))
    local line = at[it.id]
    if line then qty = qty + line.qty end                     -- (the same id twice is one line: the stock count is checked on the sum)
    if it.count and qty > it.count then return nil, strings.t('shops.not_in_stock') end
    local each = M.price(it, ctx)
    if line then line.qty, line.sum = qty, each * qty
    else line = { id = it.id, name = it.name, qty = qty, each = each, sum = each * qty } at[it.id] = line lines[#lines + 1] = line end
  end
  if shop.goods == 'tyres' and (#lines ~= 1 or lines[1].qty ~= 1) then return nil, strings.t('shops.one_set') end
  for _, l in ipairs(lines) do total = total + l.sum end
  if total > (money or 0) then return nil, strings.t('shops.cannot_afford'), total end
  return lines, total
end

return M
