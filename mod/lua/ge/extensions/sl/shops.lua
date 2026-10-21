-- Street Legal: the shops (extension name: sl_shops; docs/MODDING_SHOPS.md). Rules in sl/core/shops, the screen is ui/modModules/slShop.
-- A shop is opened by name: sl_shops.open('exhaust', { name = ..., stock = ... }), from a marker (a level's street_legal_shops.json, or a mod's settings/street_legal/shops/*.json:
-- { "shops": [ { "kind": "tyre", "name": "...", "pos": [x, y, z], ... } ] }), or by another mod. Buying: money goes through sl_career.addMoney; what is handed over depends on the goods:
--   tyres      sl_tyrecare.changeNow (it charges for the fit itself, with the trade-in)
--   catalog    parts for the player's car from Wrench Works (slrr_garage.lookupParts): bought parts go on the shelf of the car's model (slrr_garage.addShelfPart); nothing of the catalogue is copied here
--   others     the opener's opts.onBuy(lines, total) when it is a function, and the hook onStreetLegalShopBought(shopId, kind, lines, total) for every other mod
-- Nothing here writes into the career save.

local M = {}

local strings = require('sl/core/strings')
local rules = require('sl/core/shops')
local hours = require('sl/core/hours')
local dealersRules = require('sl/core/dealers')      -- (its clock: game hours since the start)

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

-- a position another mod passes (a vec3, { x, y, z } or { x, y, z } as a list) as a vec3; nil when it is none of them (the shop then does not close by distance)
local function asVec(p)
  if type(p) ~= 'table' then return nil end
  local x, y, z = tonumber(p.x or p[1]), tonumber(p.y or p[2]), tonumber(p.z or p[3])
  if not (x and y and z and vec3) then return nil end
  return vec3(x, y, z)
end

-- price modifiers other mods register (a sponsor's discount): id -> fn(item, shop) -> factor (1 = the price as it is); the factors multiply
local factors = {}
function M.setPriceFactor(id, fn)
  if type(id) ~= 'string' or id == '' then return false, 'an id is needed' end
  if fn ~= nil and type(fn) ~= 'function' then return false, 'a function (or nil to remove it) is needed' end
  factors[id] = fn
  return true
end

local function ctx(s, shop)
  return { repDiscount = true, tier = tierOf(s), wearPriced = true, favour = 0,
    factorOf = function(item)
      local f = 1
      for _, fn in pairs(factors) do
        local ok, v = pcall(fn, item, shop and { kind = shop.kind, name = shop.name, brand = shop.brand })
        v = ok and tonumber(v) or nil
        if v and v == v then f = f * v end
      end
      return f
    end }
end

-- the player's car and its world vehicle id (the car the parts are for)
local function playerCar()
  local car = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  local veh = car and sl_fleet.vehicleOf and sl_fleet.vehicleOf(car.id)
  return car, veh and veh:getID()
end

-- an option of 9e's style kit (Reduce motion): absent in a build that does not have it yet, which reads as off
local function optionOn(key) return sl_options ~= nil and sl_options.get ~= nil and sl_options.get(key) == true end

local function brandsText(list) return table.concat(list or {}, ', ') end

-- the stock of a catalogue shop: the parts that fit the player's car (Wrench Works, read only), one line each. Returns the lines, the entries by line id, the car's model and a note that says why there is
-- nothing (nil when there is something). shop.sections limits the chapters, shop.brands the brands
local function catalogStock(shop)
  local car, vid = playerCar()
  if not (slrr_garage and slrr_garage.lookupParts and slrr_garage.addShelfPart) then return {}, {}, nil, strings.t('shops.need_ww') end
  if not (car and vid) then return {}, {}, nil, strings.t('shops.bring_car') end
  local list, model = slrr_garage.lookupParts(vid, { sections = shop.sections, brands = shop.brands })
  if type(list) ~= 'table' then return {}, {}, nil, strings.t('shops.no_parts_data') end
  local lines, entries = {}, {}
  for i, e in ipairs(list) do
    local id = 'p' .. i
    entries[id] = e
    lines[#lines + 1] = { id = id, name = e.name, group = e.slot, price = e.price, brand = e.brand, count = 4, desc = e.more and strings.t('shops.has_options') or nil }
  end
  local note
  if #lines == 0 then
    if shop.brands then note = strings.t('shops.nothing_fits_brands', car.name or model or '?', brandsText(shop.brands))
    else note = strings.t('shops.nothing_fits', car.name or model or '?') end
  end
  return lines, entries, model, note
end

-- the services of a shop that sells jobs, from the state of the player's car: { services, note }
local function serviceList(shop)
  local car, vid = playerCar()
  if shop.kind == 'paint' then
    if not (sl_surfacefx and sl_surfacefx.level) then return {}, strings.t('shops.need_csfx') end
    if not (car and vid) then return {}, strings.t('shops.bring_car') end
    local level = sl_surfacefx.level(vid)
    if not level then return {}, strings.t('shops.need_csfx') end
    return rules.paintServices(level), nil
  elseif shop.kind == 'tuner' then
    if not (car and vid) then return {}, strings.t('shops.bring_car') end
    if not (slrr_garage and slrr_garage.lookupParts) then return {}, strings.t('shops.need_ww') end      -- (the dyno is the garage mod's: slrrGarageVeh)
    return rules.tunerServices(), nil
  end
  return {}, nil
end

-- does one booked service on the player's car. Returns ok, text
local function perform(line)
  local car, vid = playerCar()
  if not (car and vid) then return false, strings.t('shops.bring_car') end
  local id = line.id
  if id == 'wash' then
    if not (sl_surfacefx and sl_surfacefx.washOff and sl_surfacefx.washOff(vid)) then return false, strings.t('shops.need_csfx') end
    return true
  elseif id == 'polish' then
    if not (sl_surfacefx and sl_surfacefx.repair and sl_surfacefx.repair(vid)) then return false, strings.t('shops.need_csfx') end
    return true
  elseif id == 'dyno' then
    local veh = getObjectByID and getObjectByID(vid)
    if not veh then return false, strings.t('shops.not_here') end
    veh:queueLuaCommand('extensions.load("slrrGarageVeh") slrrGarageVeh.dyno()')
    at.dynoVid = vid
    return true, strings.t('shops.dyno_running')
  end
  local hexs, r, g, b = rules.resprayColour(id)
  if hexs then
    if not (core_vehicle_colors and core_vehicle_colors.setVehiclePaint) then return false, strings.t('shops.not_here') end
    local paint = { baseColor = { r, g, b, 1.2 }, metallic = 0.25, roughness = 0.35, clearcoat = 0.9, clearcoatRoughness = 0.05 }
    local ok = pcall(core_vehicle_colors.setVehiclePaint, 1, paint, vid)
    if not ok then return false, strings.t('shops.not_here') end
    if sl_surfacefx then pcall(sl_surfacefx.wash, vid) pcall(sl_surfacefx.repair, vid) end      -- (a paint job leaves the car clean and unscratched)
    return true
  end
  return false, strings.t('shops.no_such_service')
end

local function clockNow(s) return dealersRules.clock(s.day, sl_career.hour and sl_career.hour() or 0) end

-- the record the screen gets: the shop, its day's stock with the player's prices, the money, and why it is closed (nil: open)
local function view(shop, s)
  local c = ctx(s, shop)
  local out = { kind = shop.kind, title = shop.title, name = shop.name, brand = shop.brand, theme = shop.theme, screen = shop.screen, keeper = shop.keeper, goods = shop.goods, sections = shop.sections, reduceMotion = optionOn('slReduceMotion'),
    money = s.money or 0, stock = {}, services = {}, colorBlind = sl_options ~= nil and sl_options.get ~= nil and sl_options.get('slColorBlind') == true }
  local words = rules.WORDS[shop.kind]
  if words then out.words = { add = strings.t(words.add), buy = strings.t(words.buy) } out.tagline = strings.t(words.tag) end
  local csfx = shop.goods == 'tyres' and select(2, pcall(require, 'csfx_tyrerules')) or nil      -- (the real numbers of each compound: Car Surface FX's rules)
  local quotes = shop.goods == 'tyres' and sl_tyrecare and sl_tyrecare.quotes and sl_tyrecare.quotes('garage') or nil      -- (what the counter really charges: the trade-in is in it)
  for _, it in ipairs(shop.full and shop.stock or rules.dayStock(shop, s.day)) do
    if shop.goods == 'tyres' then
      out.stock[#out.stock + 1] = { id = it.id, name = it.name, group = it.group, desc = quotes and it.desc or strings.t('shops.price_before_trade_in'), count = 1, price = quotes and quotes[it.id] or it.price, was = quotes and it.price > quotes[it.id] and it.price or nil,
        specs = rules.tyreSpecs(it.id, csfx) }
    else
      out.stock[#out.stock + 1] = { id = it.id, name = it.name, group = it.group, desc = it.desc, cond = it.cond, count = it.count, price = rules.price(it, c), was = it.price,
        specs = it.specs, swatch = it.swatch, curve = it.curve, curveLabel = it.curveLabel, brand = it.brand }
    end
  end
  for _, sv in ipairs(shop.services) do
    out.services[#out.services + 1] = { id = sv.id, name = sv.name, desc = sv.desc, minutes = sv.minutes, price = rules.price(sv, c), specs = sv.specs, swatch = sv.swatch, curve = sv.curve, curveLabel = sv.curveLabel }
  end
  out.note = shop.note
  if shop.order then
    local s2 = career()
    out.orders = {}
    for _, o in ipairs(s2 and s2.shopOrders or {}) do
      if o.shop == shop.name then out.orders[#out.orders + 1] = { name = o.name, hours = math.max(0, math.ceil((o.due or 0) - clockNow(s2))) } end
    end
  end
  local t = dayTime()
  if sl_career and sl_career.phase and sl_career.phase() == 'night' and (shop.hoursKind == 'shop' or shop.hoursKind == 'dealer') and not shop.hours then
    out.closed = strings.t('shops.closed_morning')      -- (the career's night shuts the counters, as it shuts the lots)
  elseif t then
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
  local entries, model
  if shop.goods == 'catalog' and #shop.stock == 0 then
    shop.stock, entries, model, shop.note = catalogStock(shop)
    shop.full = true
  end
  if shop.goods == 'services' and #shop.services == 0 then
    local list, note = serviceList(shop)
    for _, sv in ipairs(list) do shop.services[#shop.services + 1] = sv end
    shop.note = note
  end
  at = { entries = entries, model = model, id = tostring(type(opts) == 'table' and opts.id or shop.name), shop = shop, pos = asVec(type(opts) == 'table' and opts.pos or nil), onBuy = type(opts) == 'table' and type(opts.onBuy) == 'function' and opts.onBuy or nil }
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
  for _, it in ipairs(shop.full and shop.stock or rules.dayStock(shop, s.day)) do day[#day + 1] = it end
  local priced = { kind = shop.kind, name = shop.name, goods = shop.goods, stock = day, services = shop.services }
  local tyres = shop.goods == 'tyres'
  local lines, total = rules.checkout(priced, parseCart(text), tyres and math.huge or s.money or 0, ctx(s, shop))      -- (tyres: the counter charges its own price, with the trade-in, and checks the money itself)
  if not lines then return toast(total) end
  if tyres then
    local ok, msg = false, strings.t('shops.not_here')
    if sl_tyrecare and sl_tyrecare.changeNow then ok, msg = sl_tyrecare.changeNow(lines[1].id, 'garage') end
    toast(msg)
    if ok then guihooks.trigger('slShopOpen', view(shop, career() or s)) end
    return
  end
  -- the money first, then the goods: a refusal or an error in onBuy gives the money back
  local special = (shop.goods == 'services' and not at.onBuy) or (at.entries and shop.order)      -- (jobs and special orders take their money themselves, below)
  if not special and total > 0 and not sl_career.addMoney(-total, shop.name) then return toast(strings.t('shops.cannot_afford')) end
  if shop.goods == 'services' and not at.onBuy then      -- a job done on the car: paid first, each line done, the lines that could not be done refunded
    if total > 0 and not sl_career.addMoney(-total, shop.name) then return toast(strings.t('shops.cannot_afford')) end
    local kept, texts = 0, {}
    for _, l in ipairs(lines) do
      local ok, text = perform(l)
      if ok then kept = kept + l.sum else
        if l.sum > 0 then sl_career.addMoney(l.sum, strings.t('shops.refund', shop.name)) end
      end
      if text then texts[#texts + 1] = text end
    end
    toast(texts[1] or strings.t('shops.paint_done'))
    if kept > 0 and extensions and extensions.hook then extensions.hook('onStreetLegalShopBought', at.id, shop.kind, lines, kept) end
    guihooks.trigger('slShopOpen', view(shop, career() or s))
    return
  end
  if at.entries and shop.order then      -- special order: a deposit now, the parts after some hours
    local deposit = rules.deposit(total)
    if deposit > 0 and not sl_career.addMoney(-deposit, shop.name) then return toast(strings.t('shops.cannot_afford')) end
    s.shopOrders = s.shopOrders or {}
    local first
    for _, o in ipairs(rules.newOrders(shop.name, at.model, at.entries, lines, total > 0 and deposit / total or 1, clockNow(s))) do
      s.shopOrders[#s.shopOrders + 1] = o
      first = first or o
    end
    toast(strings.t('shops.ordered', deposit, first and first.name or '', first and rules.orderHours(first.price) or 0))
    if extensions and extensions.hook then extensions.hook('onStreetLegalShopBought', at.id, shop.kind, lines, deposit) end
    guihooks.trigger('slShopOpen', view(shop, career() or s))
    return
  end
  if at.entries then      -- parts for the player's car go on the shelf of its model
    local paid, failed = 0, false      -- what is on the shelf is kept and paid for; only the parts that did not get there are refunded
    for _, l in ipairs(lines) do
      local e = at.entries[l.id]
      for _ = 1, l.qty do
        if not failed then
          local ok = pcall(slrr_garage.addShelfPart, at.model, { part = e.part, name = e.name, slotId = e.slotId, value = l.each })
          if ok then paid = paid + l.each else failed = true end
        end
      end
    end
    if failed then
      if total - paid > 0 then sl_career.addMoney(total - paid, strings.t('shops.refund', shop.name)) end
      toast(strings.t('shops.not_here'))
      if paid == 0 then return end
      total = paid
    end
    toast(strings.t('shops.on_the_shelf', total))
  elseif at.onBuy then
    local ok, accepted = pcall(at.onBuy, lines, total)
    if not ok or accepted == false then
      if total > 0 then sl_career.addMoney(total, strings.t('shops.refund', shop.name)) end
      return toast(strings.t('shops.not_here'))
    end
  end
  if extensions and extensions.hook then extensions.hook('onStreetLegalShopBought', at.id, shop.kind, lines, total) end
  if not at.entries then toast(strings.t('shops.bought', total)) end
  guihooks.trigger('slShopOpen', view(shop, career() or s))
end

-- ---- the shops placed on the map: a level's street_legal_shops.json and a mod's settings/street_legal/shops/*.json
local function readPlaced()
  placed = {}
  local files = {}
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  if level then files[#files + 1] = '/levels/' .. level .. '/street_legal_shops.json' end
  if FS and FS.findFiles then      -- (the map's and mods' files in /street_legal/shops/, the player's own in /settings/street_legal/shops/)
    for _, dir in ipairs({ '/street_legal/shops/', '/settings/street_legal/shops/' }) do
      for _, f in ipairs(FS:findFiles(dir, '*.json', -1, false, false) or {}) do files[#files + 1] = f end
    end
  end
  for _, file in ipairs(files) do
    local data = jsonReadFile and FS and FS:fileExists(file) and jsonReadFile(file)
    if type(data) == 'table' and data.level and level and data.level ~= level then data = nil end      -- (a file for another level: "level": "west_coast_usa")
    for i, rec in ipairs(type(data) == 'table' and data.shops or {}) do
      local kind, o = rules.fromMarker(rec)
      local p = type(rec) == 'table' and rec.pos
      if kind and type(p) == 'table' and tonumber(p[1]) and tonumber(p[2]) and tonumber(p[3]) then
        local id = tostring(rec.id or (file .. '#' .. i))
        o.id, o.pos = id, vec3(p[1], p[2], p[3])
        placed[id] = { id = id, kind = kind, name = tostring(o.name or kind), pos = o.pos, opts = o, replaces = type(o.replaces) == 'string' and o.replaces or nil }
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
    local place = type(elem.placeId) == 'string' and sl_career.getPlaces and (sl_career.getPlaces() or {})[elem.placeId]      -- (the lot's marker of a dealer: a second button beside Look at the cars)
    local brands = place and place.kind == 'dealer' and M.brandsOfPlace(place)
    if brands then
      table.insert(activityData, {
        icon = 'poi_arrival_round', heading = place.name, preheadings = { strings.t('shops.dealer_parts_heading') },
        sorting = { type = 'slrrPlace', id = place.id },
        buttonLabel = strings.t('shops.parts_counter', brandsText(brands)), buttonFun = function() M.open('dealerparts', { name = place.name, brands = brands, id = 'dealer:' .. tostring(place.id), pos = place.pos }) end,
        buttonSoundClass = 'bng_hover_generic',
      })
    end
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

-- ---- a dealer's parts counter: the brands on the dealer's sign (/street_legal/shops/dealer_brands.json: { "<level>": { "<place id, stock id or name>": [ "Brand", ... ] } })
local dealerBrands
local function brandsOfPlace(place)
  if dealerBrands == nil then
    local data = jsonReadFile and FS and FS:fileExists('/street_legal/shops/dealer_brands.json') and jsonReadFile('/street_legal/shops/dealer_brands.json')
    dealerBrands = type(data) == 'table' and data or {}
  end
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  local t = level and dealerBrands[level]
  if type(t) ~= 'table' or type(place) ~= 'table' then return nil end
  for _, key in ipairs({ place.id, place.stockId, place.name }) do
    local list = key and t[key]
    if type(list) == 'table' and #list > 0 then return list end
  end
end
M.brandsOfPlace = brandsOfPlace

-- Wrench Works' own parts counters (blue markers) that a shop of ours stands at are ours: it does not open its screen there
local overrideSet
local function setOverride(on)
  if (overrideSet == true) == (on == true) then return end      -- (only a change reaches Wrench Works; nothing at all without a career)
  if not (slrr_garage and slrr_garage.setShopOverride) then return end
  if on and not career() then return end
  overrideSet = on
  slrr_garage.setShopOverride(on and function(site)
    if next(placed) == nil and career() then readPlaced() end
    for _, p in pairs(placed) do if p.replaces == site.id then return true end end
    return false
  end or nil)
end

-- walked or driven away: it closes
local timer = 0
local orderTimer, told = 0, {}
local function deliverOrders(s)
  if not (slrr_garage and slrr_garage.addShelfPart) then return end
  local list = s.shopOrders or {}
  for _, o in ipairs(rules.ready(list, clockNow(s))) do
    local balance = math.max(0, (o.price or 0) - (o.paid or 0))
    if (s.money or 0) < balance then
      if not told[o] then
        told[o] = true
        sl_career.sendText('benny', strings.t('shops.order_waiting', o.name or '?', o.shop or '?', balance), 2)
      end
    elseif balance == 0 or sl_career.addMoney(-balance, o.shop) then
      local ok = pcall(slrr_garage.addShelfPart, o.model, { part = o.part, name = o.name, slotId = o.slotId, value = o.price })
      if ok then
        for i, x in ipairs(list) do if x == o then table.remove(list, i) break end end
        sl_career.sendText('benny', strings.t('shops.order_arrived', o.name or '?', o.shop or '?', balance), 2)
      elseif balance > 0 then
        sl_career.addMoney(balance, strings.t('shops.refund', o.shop or ''))
      end
    end
  end
end

-- the dyno run of a tuner shop is done: the figures and the curve go to the screen (Wrench Works' vehicle side reports it)
function M.onWrenchWorksDyno(id, data)
  if not (at and at.dynoVid and at.dynoVid == id and type(data) == 'table' and data.maxPower) then return end
  at.dynoVid = nil
  guihooks.trigger('slShopResult', { title = strings.t('shops.svc_dyno'), curve = data.power, curveLabel = strings.t('shops.dyno_peak_power'),
    lines = { { label = strings.t('shops.dyno_peak_power'), text = string.format('%d hp at %d rpm', data.maxPower or 0, data.maxPowerRPM or 0) },
      { label = strings.t('shops.dyno_peak_torque'), text = string.format('%d Nm at %d rpm', data.maxTorque or 0, data.maxTorqueRPM or 0) } } })
end

function M.onUpdate(dtReal)
  orderTimer = orderTimer + (dtReal or 0)
  if orderTimer > 5 then
    orderTimer = 0
    local s = career()
    if s and s.shopOrders and #s.shopOrders > 0 then pcall(deliverOrders, s) end
  end
  if not at then return end
  timer = timer + (dtReal or 0)
  if timer < 1 then return end
  timer = 0
  local v = getPlayerVehicle(0)
  local far = false
  if v and at.pos then
    local ok, d = pcall(function() return (v:getPosition() - at.pos):length() end)
    far = ok and d > 25
  end
  if not career() or not v or far then M.close() end
end

local function refresh() if gameplay_rawPois and gameplay_rawPois.clear then gameplay_rawPois.clear() end end
M.onStreetLegalStarted = function() refresh() setOverride(true) end
M.onStreetLegalStopped = function() refresh() setOverride(false) M.close() end
M.onClientStartMission = function() dealerBrands = nil end

require('sl/core/features').gate('shops', M, nil, nil, { 'open', 'buy' }, { 'onStreetLegalStarted' })

return M
