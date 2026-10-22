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
  performance = { title = 'Performance shop',   goods = 'catalog',  screen = 'catalogue', theme = { accent = '#d9575f', pattern = 'chevrons', icon = 'engine' },   hours = 'shop', order = true, sections = { 'intake', 'forced', 'internals', 'management', 'cooling', 'fuel' } },
  paint =       { title = 'Paint and body',     goods = 'services', screen = 'services',  theme = { accent = '#9b8cf0', pattern = 'spray',    icon = 'paint' },    hours = 'shop' },
  tuner =       { title = 'Tuner',              goods = 'services', screen = 'services',  theme = { accent = '#5fb7e6', pattern = 'dyno',     icon = 'gauge' },    hours = 'shop' },
  mechanic =    { title = 'Mechanic',           goods = 'services', screen = 'services',  theme = { accent = '#b0b8c4', pattern = 'bolts',    icon = 'spanner' },  hours = 'shop' },
  accessories = { title = 'Accessories',        goods = 'given',    screen = 'catalogue', theme = { accent = '#e86fb0', pattern = 'stripes',  icon = 'star' },     hours = 'shop' },
  carwash =     { title = 'Car wash',           goods = 'services', screen = 'services',  theme = { accent = '#4fc3f7', pattern = 'bubbles',  icon = 'drop' },     hours = 'shop' },
  junkyard =    { title = 'Junkyard parts',     goods = 'catalog',  screen = 'catalogue', theme = { accent = '#c0a16b', pattern = 'rust',     icon = 'crate' },    hours = 'junkyard', used = true },
  diner =       { title = 'Diner',              goods = 'given',    screen = 'catalogue', theme = { accent = '#e8a23d', pattern = 'checks',   icon = 'cup' },      hours = 'always' },
  motel =       { title = 'Motel',              goods = 'services', screen = 'services',  theme = { accent = '#7e8fd6', pattern = 'stars',    icon = 'bed' },      hours = 'always' },
  dealerparts = { title = 'Dealer parts',       goods = 'catalog',  screen = 'catalogue', theme = { accent = '#8ab4f8', pattern = 'badge',    icon = 'badge' },    hours = 'dealer' },
}
M.ORDER = { 'tyre', 'exhaust', 'parts', 'performance', 'paint', 'tuner', 'mechanic', 'accessories', 'dealerparts', 'diner', 'motel', 'carwash', 'junkyard' }
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
  carwash = { tag = 'shops.tag_carwash', add = 'shops.word_book', buy = 'shops.word_book_pay' },
  junkyard = { tag = 'shops.tag_junkyard', add = 'shops.word_pull', buy = 'shops.word_pay' },
  diner = { tag = 'shops.tag_diner', add = 'shops.word_order_food', buy = 'shops.word_eat' },
  motel = { tag = 'shops.tag_motel', add = 'shops.word_book', buy = 'shops.word_book_pay' },
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
  if it.brand ~= nil then out.brand = tostring(it.brand):sub(1, 40) end      -- (a part brand: wrench works slrr_brands)
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
  local function texts(list)
    local out = {}
    for _, v in ipairs(type(list) == 'table' and list or {}) do if type(v) == 'string' and v ~= '' then out[#out + 1] = v end end
    return #out > 0 and out or nil
  end
  s.used = t.used == true or opts.used == true          -- (second-hand parts: a day's pick of the catalogue at a discount, worn)
  s.order = t.order == true or opts.order == true       -- (special order: a deposit now, the parts after some hours)
  s.sections = texts(opts.sections) or s.sections      -- (a shop of this kind may sell other chapters: "engine/exhaust", "engine/intake")
  s.brands = texts(opts.brands)                          -- (only parts of these brands: a dealer's counter)
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
  o.stock, o.services, o.range, o.sections, o.brands, o.replaces = f.stock, f.services, f.range, f.sections, f.brands, f.replaces
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

-- ---- paint and body: what the shop does for a car, from the state Car Surface FX keeps (level = sl_surfacefx.level: { dirtName = clean | dusty | muddy, scratchName = none | light | heavy }; nil without the mod)
M.WASH_PRICE = 15            -- = sl/station WASH_PRICE
M.POLISH_PRICE = { light = 80, heavy = 190 }
M.RESPRAY_PRICE = 450
M.COLOURS = { { '#c0392b', 'Signal red' }, { '#1f2a44', 'Midnight blue' }, { '#1e5b3a', 'Racing green' }, { '#f1c40f', 'Signal yellow' }, { '#ecf0f1', 'Pearl white' },
  { '#4b5563', 'Gunmetal' }, { '#e67e22', 'Burnt orange' }, { '#111111', 'Gloss black' } }

function M.paintServices(level)
  local out = {}
  if type(level) ~= 'table' then return out end
  if level.dirtName and level.dirtName ~= 'clean' then out[#out + 1] = { id = 'wash', name = strings.t('shops.svc_wash'), price = M.WASH_PRICE, desc = strings.t('shops.svc_wash_desc') } end
  local polish = M.POLISH_PRICE[level.scratchName or '']
  if polish then out[#out + 1] = { id = 'polish', name = strings.t('shops.svc_polish'), price = polish, desc = strings.t('shops.svc_polish_desc') } end
  for _, c in ipairs(M.COLOURS) do
    out[#out + 1] = { id = 'respray_' .. c[1]:sub(2), name = strings.t('shops.svc_respray', c[2]), price = M.RESPRAY_PRICE, swatch = c[1], desc = strings.t('shops.svc_respray_desc') }
  end
  return out
end

-- the colour of a respray line id ('respray_c0392b' -> '#c0392b' and its r, g, b in 0..1), nil for anything else
function M.resprayColour(id)
  local hexs = type(id) == 'string' and id:match('^respray_(%x%x%x%x%x%x)$')
  if not hexs then return nil end
  local function c(i) return tonumber(hexs:sub(i, i + 1), 16) / 255 end
  return '#' .. hexs:lower(), c(1), c(3), c(5)
end

-- ---- the car wash: what it does for a car (level = sl_surfacefx.level: { dirtName, scratchName }); nil without Car Surface FX. There is no wax: the mod has no call to slow the dirt
M.WASH_BASIC, M.WASH_POLISH = 15, 45
function M.washServices(level)
  local out = {}
  if type(level) ~= 'table' then return out end
  local dirty = level.dirtName ~= nil and level.dirtName ~= 'clean'
  local scratched = level.scratchName ~= nil and level.scratchName ~= 'none'
  if dirty then out[#out + 1] = { id = 'basicwash', name = strings.t('shops.svc_wash'), price = M.WASH_BASIC, desc = strings.t('shops.svc_wash_desc') } end
  if dirty or scratched then out[#out + 1] = { id = 'washpolish', name = strings.t('shops.svc_washpolish'), price = scratched and M.WASH_POLISH or M.WASH_BASIC + 10, desc = strings.t('shops.svc_washpolish_desc') } end
  return out
end

-- ---- the independent mechanic: a service at 85% of the phone's price, an hour of the clock, and an inspection ($40: the car report)
M.MECHANIC_DISCOUNT, M.MECHANIC_HOURS, M.INSPECT_PRICE = 0.85, 1, 40
function M.mechanicServices(options)
  local out = {}
  for _, o in ipairs(options or {}) do
    if o.available ~= false then
      out[#out + 1] = { id = 'service_' .. tostring(o.id), name = tostring(o.label or o.id), price = math.floor((tonumber(o.cost) or 0) * M.MECHANIC_DISCOUNT / 10 + 0.5) * 10, desc = strings.t('shops.svc_service_desc') }
    end
  end
  out[#out + 1] = { id = 'inspect', name = strings.t('shops.svc_inspect'), price = M.INSPECT_PRICE, desc = strings.t('shops.svc_inspect_desc') }
  return out
end

-- ---- plates (accessories): a short list of plate texts, $60 each
M.PLATE_PRICE = 60
M.PLATES = { 'STREET', 'NIGHT', 'SLRR', 'DRIFT', 'APEX', 'TURBO', 'RACER', 'SHIFT' }
function M.plateStock()
  local out = {}
  for _, t in ipairs(M.PLATES) do out[#out + 1] = { id = 'plate_' .. t, name = strings.t('shops.plate_name', t), price = M.PLATE_PRICE, group = strings.t('shops.group_plates'), count = 1 } end
  return out
end
function M.plateText(id) return type(id) == 'string' and id:match('^plate_([%u%d]+)$') or nil end

-- ---- the junkyard: a day's pick of the parts that fit the car, second-hand: 35 to 65% off, worn (condition 0.3 to 0.7). The same day gives the same pick
M.JUNK_KEEP, M.JUNK_DISC_MIN, M.JUNK_DISC_MAX = 24, 0.35, 0.65
M.USED = { condMin = 0.3, condMax = 0.7 }
function M.junkSample(list, day, seed)
  local r = rng.new((day or 1) * 6151 + rng.hash(tostring(seed or '')))
  local pool = {}
  for i, e in ipairs(list or {}) do pool[i] = e end
  for i = #pool, 2, -1 do local j = r:int(1, i) pool[i], pool[j] = pool[j], pool[i] end      -- (a shuffle: the pick differs from day to day)
  local out = {}
  for i = 1, math.min(M.JUNK_KEEP, #pool) do
    local e = pool[i]
    local copy = {}
    for k, v in pairs(e) do copy[k] = v end
    local off = r:range(math.min(M.JUNK_DISC_MIN, M.JUNK_DISC_MAX), math.max(M.JUNK_DISC_MIN, M.JUNK_DISC_MAX))
    copy.price = math.max(1, math.floor((e.price or 0) * (1 - off) + 0.5))
    copy.cond = r:range(M.USED.condMin, M.USED.condMax)
    copy.wear = 1 - copy.cond
    out[#out + 1] = copy
  end
  table.sort(out, function(a, b) if a.sub ~= b.sub then return tostring(a.sub) < tostring(b.sub) end return a.price < b.price end)
  return out
end

-- ---- the tuner
M.DYNO_PRICE = 90
function M.tunerServices() return { { id = 'dyno', name = strings.t('shops.svc_dyno'), price = M.DYNO_PRICE, desc = strings.t('shops.svc_dyno_desc') } } end

-- ---- special orders (the performance shop): a deposit now, the parts after some hours, the balance when they arrive
M.SPECIAL = { DEPOSIT = 0.3, BASE_HOURS = 6, PER_HOURS = 300, MAX_HOURS = 48 }
function M.deposit(total) return math.min(total, math.max(1, math.ceil(total * M.SPECIAL.DEPOSIT))) end
function M.orderHours(price) return math.min(M.SPECIAL.MAX_HOURS, M.SPECIAL.BASE_HOURS + math.floor((price or 0) / M.SPECIAL.PER_HOURS)) end
-- one order per part bought: { shop, model, part, name, slotId, price, paid, due } (due in game hours, as sl/core/dealers.clock counts them)
function M.newOrders(shopName, model, entries, lines, depositShare, now)
  local out = {}
  for _, l in ipairs(lines) do
    local e = entries[l.id]
    for _ = 1, l.qty do
      out[#out + 1] = { shop = shopName, model = model, part = e.part, name = e.name, slotId = e.slotId, price = l.each, paid = math.floor(l.each * depositShare + 0.5), due = now + M.orderHours(l.each) }
    end
  end
  return out
end
-- the orders that have waited a week (168 game hours) past their time: they were never delivered (no garage mod), the deposit goes back
function M.expired(orders, now)
  local out = {}
  for _, o in ipairs(orders or {}) do if (o.due or 0) + 168 <= now then out[#out + 1] = o end end
  return out
end

-- the orders that are ready (due <= now), oldest first
function M.ready(orders, now)
  local out = {}
  for _, o in ipairs(orders or {}) do if (o.due or 0) <= now then out[#out + 1] = o end end
  table.sort(out, function(a, b) return (a.due or 0) < (b.due or 0) end)
  return out
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
  local factor = 1
  if type(ctx.factorOf) == 'function' then      -- a modifier chain (a sponsor's discount): nil-safe, an error or a nonsense number is list price, held between 0.05 and 3
    local ok, f = pcall(ctx.factorOf, item)
    f = ok and tonumber(f) or nil
    if f and f == f then factor = clamp(f, 0.05, 3) end
  end
  return math.max(0, math.floor(base * (1 - off) * factor + 0.5))
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
