-- Wrench Works: Street Legal: the used parts market (extension name: sl_classifieds; Design 4, X12). The
-- Revline app's listings: parts for the cars you own (and a few others) from private sellers round town,
-- refreshed through the day. Haggle, then pick it up at the seller's kerb (a job with a marker; a deposit
-- up front) or pay for delivery to your garage shelf. Rules in sl/core/listings; parts reach Wrench Works'
-- shelf through slrr_garage.addShelfPart, valued at what was paid.

local M = {}

local L = require('sl/core/listings')
local rngLib = require('sl/core/rng')
local jbeamIO = require('jbeam/io')         -- (not a global on the game-engine side)

local REFRESH_HOURS = 6        -- new listings every few in-game hours
local APP_LISTINGS = 12
local DELIVERY_HOURS = 6
local COMMON_MODELS = { 'covet', 'pessima', 'vivace', 'etk800', 'sunburst2', 'bastion' }
local STOP_RADIUS = 9

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) if ui_message then ui_message(text, 5, 'streetLegal') end end
local function now(s) return (s.day or 0) * 24 + math.floor(sl_career.hour and sl_career.hour() or 12) end
local function state(s)
  s.market = s.market or { listings = {}, nextId = 1, refreshed = -1e9, deliveries = {}, rounds = {} }
  return s.market
end

local NAMES = { 'Dave', 'Kenny', 'Mirela', 'Gabor', 'Big Tony', 'Sanja', 'Rudi', 'Lex', 'Old Man Fekete', 'Zsofi', 'Marco', 'Petra' }

-- parts of a model with their values (BeamNG's jbeam), cached per model
local partsCache = {}
local function partsOf(model)
  if partsCache[model] then return partsCache[model] end
  local list = {}
  local ok = pcall(function()
    local ctx = jbeamIO.startLoading({ '/vehicles/' .. model .. '/', '/vehicles/common/' })
    for name, desc in pairs(jbeamIO.getAvailableParts(ctx) or {}) do
      if not desc.isAuxiliary then
        local part = jbeamIO.getPart(ctx, name)
        local info = part and part.information or {}
        local value = tonumber(info.value) or 0
        local slot = part and (type(part.slotType) == 'table' and part.slotType[1] or part.slotType)
        if value >= 20 and type(slot) == 'string' and slot ~= 'main' then
          list[#list + 1] = { kind = 'part', part = name, name = info.name or desc.description or name, value = value, slotId = slot, model = model }
        end
      end
    end
  end)
  if not ok then list = {} end
  table.sort(list, function(a, b) return a.part < b.part end)
  partsCache[model] = list
  return list
end

local function models(s)
  local out, seen = {}, {}
  for _, c in ipairs(s.cars or {}) do if c.model and not seen[c.model] then seen[c.model] = true out[#out + 1] = c.model end end
  for _, m in ipairs(COMMON_MODELS) do if not seen[m] and FS:directoryExists('/vehicles/' .. m .. '/') then seen[m] = true out[#out + 1] = m end end
  return out
end

-- drop what expired, top the app up to APP_LISTINGS, deliver what has arrived
local function refresh(s, force)
  local m, t = state(s), now(s)
  for i = #m.deliveries, 1, -1 do
    local d = m.deliveries[i]
    if d.due <= t then
      table.remove(m.deliveries, i)
      if slrr_garage and slrr_garage.addShelfPart then
        slrr_garage.addShelfPart(d.model, d.part)
        toast(string.format('Delivered to your garage: %s (for the %s).', d.part.name, d.model))
      end
    end
  end
  if not force and t - m.refreshed < REFRESH_HOURS then return end
  m.refreshed = t
  local keep = {}
  -- a taken one stays only while its pickup is the job you are on (bought for delivery, given up: gone)
  local active = s.jobs and s.jobs.active
  for _, l in ipairs(m.listings) do
    if (l.expires > t and not l.taken) or (l.taken and active and active.listing == l.id) then keep[#keep + 1] = l end
  end
  m.listings = keep
  local rng = rngLib.new(rngLib.hash('market:' .. t .. ':' .. tostring(s.seed)))
  local ms = models(s)
  for _ = 1, 40 do
    if #m.listings >= APP_LISTINGS or #ms == 0 then break end
    local pool = partsOf(ms[rng:int(#ms)])
    if #pool > 0 then
      local item = pool[rng:int(#pool)]
      local l = L.listing(rng, item, 'app', L.demand(rng), t)
      l.id, l.seller = 'm' .. m.nextId, NAMES[rng:int(#NAMES)]
      m.nextId = m.nextId + 1
      local k = sl_jobs and sl_jobs.randomKerb and sl_jobs.randomKerb(rng)
      if k then
        l.where = { x = k.x, y = k.y, z = k.z }
        m.listings[#m.listings + 1] = l
      end
    end
  end
  extensions.hook('onStreetLegalChanged')
end

local function find(m, id) for i, l in ipairs(m.listings) do if l.id == id then return l, i end end end

-- the phone's view of the app
function M.summary()
  local s = career()
  if not s then return nil end
  refresh(s)
  local m, out = state(s), { listings = {}, deliveries = #state(s).deliveries }
  for _, l in ipairs(m.listings) do
    if not l.taken then
      out.listings[#out.listings + 1] = { id = l.id, name = l.item.name, model = l.item.model, ask = l.agreed or l.ask, condition = math.floor(l.condition * 100 + 0.5),
        seller = l.seller, rating = l.rating, tells = L.tells(l), rare = l.rare, agreed = l.agreed ~= nil,
        delivery = not l.scam and L.delivery(l.agreed or l.ask) or nil, deposit = L.deposit(l.agreed or l.ask), hoursLeft = l.expires - now(s) }
    end
  end
  return out
end

-- haggle: an offer to the seller; returns ok, text
function M.offer(id, amount)
  local s = career()
  if not s then return false, 'No career running.' end
  local m = state(s)
  local l = find(m, id)
  if not l or l.taken then return false, 'That listing is gone.' end
  local r, price = L.haggle(l, amount, m.rounds[id] or 0)
  m.rounds[id] = (m.rounds[id] or 0) + 1
  if r == 'accept' then l.agreed = price return true, string.format('%s: "Deal, $%d."', l.seller, price) end
  if r == 'counter' then l.ask = price return true, string.format('%s: "Can do $%d, no lower."', l.seller, price) end
  if r == 'walk' then l.expires = now(s) return false, l.seller .. ' stopped answering.' end
  return false, string.format('%s: "No chance."', l.seller)
end

-- buy: 'delivery' (pay it all now plus delivery; on the shelf in a few hours) or 'pickup' (a deposit now,
-- the rest at the seller's kerb)
function M.buy(id, how)
  local s = career()
  if not s then return false, 'No career running.' end
  local m = state(s)
  local l = find(m, id)
  if not l or l.taken then return false, 'That listing is gone.' end
  local price = l.agreed or l.ask
  local part = { part = l.item.part, name = l.item.name, slotId = l.item.slotId, value = price, wear = l.wear }
  if how == 'delivery' then
    if l.scam then return false, l.seller .. ': "No delivery. Deposit by transfer, then you collect."' end
    if not sl_career.addMoney(-(price + L.delivery(price)), 'Revline: ' .. l.item.name) then return false, 'Not enough money.' end
    l.taken = true
    m.deliveries[#m.deliveries + 1] = { due = now(s) + DELIVERY_HOURS, model = l.item.model, part = part }
    return true, string.format('Paid. The %s comes to your garage in about %d hours.', l.item.name, DELIVERY_HOURS)
  end
  local js = s.jobs
  if js and js.active then return false, 'Finish the job you are on first.' end
  local deposit = L.deposit(price)
  if not sl_career.addMoney(-deposit, 'Revline deposit: ' .. l.item.name) then return false, 'Not enough for the deposit.' end
  l.taken = true
  local w = l.where
  local job = { id = 'market:' .. l.id, kind = 'market', title = 'Pick up', item = l.item.name, settle = 'market', seconds = 0, pay = 0,
    legs = { { id = 'seller', name = l.seller .. "'s place", x = w.x, y = w.y, z = w.z }, { id = 'seller', name = l.seller .. "'s place", x = w.x, y = w.y, z = w.z } },
    listing = l.id, price = price, deposit = deposit, model = l.item.model, part = part, scam = l.scam, noShow = l.noShow }
  js = js or { offers = {}, done = 0, earned = 0 }
  s.jobs = js
  js.offers = js.offers or {}
  js.offers[#js.offers + 1] = job
  local ok, text = sl_jobs.take(job.id)
  return ok, ok and string.format('Deposit $%d paid. %s is expecting you.', deposit, l.seller) or text
end

-- the pickup: at the seller's kerb, slow - pay the rest and the part goes on the shelf (or not, if it was a scam
-- or nobody comes out)
local timer = 0
function M.onUpdate(dtReal)
  local s = career()
  if not s then return end
  timer = timer + (dtReal or 0)
  if timer < 0.5 then return end
  timer = 0
  refresh(s)
  local js = s.jobs
  local j = js and js.active
  if not j or j.settle ~= 'market' then return end
  local v = getPlayerVehicle(0)
  if not v then return end
  local stop = j.legs[1]
  if (v:getPosition() - vec3(stop.x, stop.y, stop.z or 0)):length() > STOP_RADIUS or v:getVelocity():length() > 2 then return end
  local m = state(s)
  local _, i = find(m, j.listing)
  if i then table.remove(m.listings, i) end
  if j.scam then
    sl_jobs.cancel(s, js, j, string.format('Nobody here has heard of "%s". The deposit ($%d) is gone.', (stop.name:gsub("'s place", '')), j.deposit))
  elseif j.noShow then
    sl_career.addMoney(j.deposit, 'Revline deposit back')
    sl_jobs.cancel(s, js, j, 'Nobody came out. The deposit came back, at least.')
  elseif not sl_career.addMoney(-(j.price - j.deposit), 'Revline: ' .. j.item) then
    toast(string.format('The seller wants $%d more, and you have not got it.', j.price - j.deposit))
    return
  else
    if slrr_garage and slrr_garage.addShelfPart then slrr_garage.addShelfPart(j.model, j.part) end
    sl_jobs.cancel(s, js, j, string.format('Got the %s. It is on your shelf for the %s.', j.item, j.model))
  end
end

return M
