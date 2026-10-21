-- Street Legal: the shops (extension name: sl_shops; docs/MODDING_SHOPS.md). Rules in sl/core/shops, the screen is ui/modModules/slShop.
-- A shop is opened by name: sl_shops.open('exhaust', { name = ..., stock = ... }), from a marker (a level's street_legal_shops.json, or a mod's settings/street_legal/shops/*.json:
-- { "shops": [ { "kind": "tyre", "name": "...", "pos": [x, y, z], ... } ] }), or by another mod. Buying: money goes through sl_career.addMoney; what is handed over depends on the goods:
--   tyres      sl_tyrecare.changeNow (it charges for the fit itself, with the trade-in)
--   others     the opener's opts.onBuy(lines, total) when it is a function, and the hook onStreetLegalShopBought(shopId, kind, lines, total) for every other mod
-- Nothing here writes into the career save.

local M = {}

local strings = require('sl/core/strings')
local rules = require('sl/core/shops')
local hours = require('sl/core/hours')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) if text then guihooks.trigger('slPhoneToast', { text = text }) end end

local at          -- the shop open now: { id, shop, pos, onBuy, tier }
local placed = {} -- the shops placed on the map: id -> { id, kind, name, pos = vec3, opts }

local function dayTime()
  local tod = core_environment and core_environment.getTimeOfDay and core_environment.getTimeOfDay()
  return type(tod) == 'table' and tod.time or nil      -- (the engine's day fraction, noon = 0)
end

-- the discount tier of the player: one per 500 reputation (the discount is 1% a tier up to 8%)
local function tierOf(s) return math.floor(math.max(0, s.rep or 0) / 500) end

local function ctx(s) return { repDiscount = true, tier = tierOf(s), wearPriced = true, favour = 0 } end

-- the record the screen gets: the shop, its day's stock with the player's prices, the money, and why it is closed (nil: open)
local function view(shop, s)
  local c = ctx(s)
  local out = { kind = shop.kind, title = shop.title, name = shop.name, brand = shop.brand, theme = shop.theme, screen = shop.screen, keeper = shop.keeper, goods = shop.goods, sections = shop.sections,
    money = s.money or 0, stock = {}, services = {}, colorBlind = sl_options ~= nil and sl_options.get ~= nil and sl_options.get('slColorBlind') == true }
  for _, it in ipairs(rules.dayStock(shop, s.day)) do
    out.stock[#out.stock + 1] = { id = it.id, name = it.name, group = it.group, desc = it.desc, cond = it.cond, count = it.count, price = rules.price(it, c), was = it.price }
  end
  for _, sv in ipairs(shop.services) do
    out.services[#out.services + 1] = { id = sv.id, name = sv.name, desc = sv.desc, minutes = sv.minutes, price = rules.price(sv, c) }
  end
  local t = dayTime()
  if t then
    local open = shop.hours and rules.isOpen(shop, (t * 24 + 12) % 24) or (not shop.hours and hours.isOpen(shop.hoursKind, t))
    if not open then
      local from = shop.hours and shop.hours[1] or hours.opensAt(shop.hoursKind) or 8
      out.closed = strings.t('shops.closed', string.format('%02d', from))
    end
  end
  return out
end

-- opens the screen of a shop kind. opts: name, brand, hours = { open, close }, keeper = { name, line }, theme = { accent }, stock = { { id, name, price, cond, group, desc, count } },
-- services = { { id, name, price, minutes, desc } }, range ('torres' | 'race', tyre shops), onBuy = function(lines, total), id (a name for the hook). Returns true, or false and the reason.
function M.open(kind, opts)
  local s = career()
  if not s then return false, strings.t('shops.no_career') end
  local shop, why = rules.normalize(kind, opts)
  if not shop then return false, why end
  at = { id = tostring(type(opts) == 'table' and opts.id or shop.name), shop = shop, pos = type(opts) == 'table' and opts.pos or nil, onBuy = type(opts) == 'table' and type(opts.onBuy) == 'function' and opts.onBuy or nil }
  if sl_phone and sl_phone.requestStrings then sl_phone.requestStrings() end
  guihooks.trigger('slShopOpen', view(shop, s))
  return true
end

function M.close()
  if not at then return end
  at = nil
  guihooks.trigger('slShopClose', {})
end

-- another mod adds a kind of shop (see docs/MODDING_SHOPS.md)
function M.define(kind, def) return rules.define(kind, def) end
function M.kinds() return rules.kinds() end
function M.isOpen() return at ~= nil end

-- the screen buys: `cart` is "id:qty,id:qty" (ids are letters, digits, _ . -)
local function parseCart(text)
  local cart = {}
  for id, qty in tostring(text or ''):gmatch('([%w_%.%-]+):(%d+)') do cart[#cart + 1] = { id = id, qty = tonumber(qty) } end
  return cart
end

function M.buy(text)
  local s = career()
  if not (s and at) then return end
  local shop = at.shop
  local current = view(shop, s)
  if current.closed then return toast(current.closed) end
  local day = {}
  for _, it in ipairs(rules.dayStock(shop, s.day)) do day[#day + 1] = it end
  local priced = { kind = shop.kind, name = shop.name, stock = day, services = shop.services }
  local lines, total = rules.checkout(priced, parseCart(text), s.money or 0, ctx(s))
  if not lines then return toast(total) end
  if shop.goods == 'tyres' then
    local line = lines[1]
    local ok, msg = false, strings.t('shops.not_here')
    if sl_tyrecare and sl_tyrecare.changeNow then ok, msg = sl_tyrecare.changeNow(line.id, 'garage') end
    toast(msg)
    if ok then guihooks.trigger('slShopOpen', view(shop, career() or s)) end
    return
  end
  if at.onBuy then
    local ok, accepted = pcall(at.onBuy, lines, total)
    if not ok or accepted == false then return toast(strings.t('shops.not_here')) end
  end
  if total > 0 and not sl_career.addMoney(-total, shop.name) then return toast(strings.t('shops.cannot_afford')) end
  if extensions and extensions.hook then extensions.hook('onStreetLegalShopBought', at.id, shop.kind, lines, total) end
  toast(strings.t('shops.bought', total))
  guihooks.trigger('slShopOpen', view(shop, career() or s))
end

-- ---- the shops placed on the map: a level's street_legal_shops.json and a mod's settings/street_legal/shops/*.json
local function readPlaced()
  placed = {}
  local files = {}
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  if level then files[#files + 1] = '/levels/' .. level .. '/street_legal_shops.json' end
  if FS and FS.findFiles then
    for _, f in ipairs(FS:findFiles('/settings/street_legal/shops/', '*.json', -1, false, false) or {}) do files[#files + 1] = f end
  end
  for _, file in ipairs(files) do
    local data = jsonReadFile and FS and FS:fileExists(file) and jsonReadFile(file)
    for i, rec in ipairs(type(data) == 'table' and data.shops or {}) do
      local kind, o = rules.fromMarker(rec)
      local p = type(rec) == 'table' and rec.pos
      if kind and type(p) == 'table' and tonumber(p[1]) and tonumber(p[2]) and tonumber(p[3]) then
        local id = tostring(rec.id or (file .. '#' .. i))
        o.id, o.pos = id, vec3(p[1], p[2], p[3])
        placed[id] = { id = id, kind = kind, name = tostring(o.name or kind), pos = o.pos, opts = o }
      elseif log then
        log('W', 'sl_shops', file .. ' #' .. i .. ': ' .. tostring(kind and 'a shop needs "pos": [x, y, z]' or o))
      end
    end
  end
end

-- a tool for map makers and testers: stand where the shop should be and call sl_shops.placeHere('tyre', 'Torres on 5th'); the shop is written to
-- settings/street_legal/shops/placed_<n>.json at your position and its marker appears at once (delete the file to remove it). Returns true, or false and the reason
function M.placeHere(kind, name)
  if not rules.type(kind) then return false, 'unknown shop kind: ' .. tostring(kind) end
  local v = getPlayerVehicle and getPlayerVehicle(0)
  if not (v and jsonWriteFile) then return false, 'no vehicle to stand at' end
  local p = v:getPosition()
  local n = 1
  while FS and FS:fileExists('/settings/street_legal/shops/placed_' .. n .. '.json') do n = n + 1 end
  local file = '/settings/street_legal/shops/placed_' .. n .. '.json'
  local ok = jsonWriteFile(file, { shops = { { kind = kind, name = name or rules.type(kind).title, pos = { math.floor(p.x * 100 + 0.5) / 100, math.floor(p.y * 100 + 0.5) / 100, math.floor(p.z * 100 + 0.5) / 100 } } } }, true)
  if not ok then return false, 'could not write ' .. file end
  if gameplay_rawPois and gameplay_rawPois.clear then gameplay_rawPois.clear() end
  return true, file
end

function M.placed() return placed end

-- the game asks every extension for its markers once per level (cached)
function M.onGetRawPoiListForLevel(level, elements)
  if not career() then return end
  readPlaced()
  for id, p in pairs(placed) do
    elements[#elements + 1] = { id = 'sl_shop_' .. id, data = { type = 'slrrShop', id = id, name = p.name, kind = p.kind, date = 0 },
      markerInfo = { missionMarker = { pos = p.pos, rot = quat(0, 0, 0, 1), icon = 'mission_arrival_triangle' } } }
  end
end

function M.onActivityAcceptGatherData(elemData, activityData)
  if not career() then return end
  for _, elem in ipairs(elemData or {}) do
    if elem.type == 'slrrShop' then
      local p = placed[elem.id]
      if p then
        table.insert(activityData, {
          icon = 'poi_arrival_round', heading = p.name, preheadings = { rules.type(p.kind).title },
          sorting = { type = 'slrrShop', id = elem.id },
          buttonLabel = strings.t('shops.go_in'), buttonFun = function() M.open(p.kind, p.opts) end,
          buttonSoundClass = 'bng_hover_generic',
        })
      end
    end
  end
end

-- walked or driven away: it closes
local timer = 0
function M.onUpdate(dtReal)
  if not at then return end
  timer = timer + (dtReal or 0)
  if timer < 1 then return end
  timer = 0
  local v = getPlayerVehicle(0)
  if not career() or not v or (at.pos and (v:getPosition() - at.pos):length() > 25) then M.close() end
end

local function refresh() if gameplay_rawPois and gameplay_rawPois.clear then gameplay_rawPois.clear() end end
M.onStreetLegalStarted = refresh
M.onStreetLegalStopped = function() refresh() M.close() end

require('sl/core/features').gate('shops', M, nil, nil, { 'open', 'buy' }, { 'onStreetLegalStarted' })

return M
