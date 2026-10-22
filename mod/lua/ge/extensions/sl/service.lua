-- Street Legal: servicing (extension name: sl_service; career expansion #2). Rules in sl/core/service. A service every ~150 km keeps the wear down; skipping it makes it faster.
-- With Part Wear installed, its per-part conditions are read (slrr_partwear.conditionsOf / conditionsOfKey, read-only) and shown per section; without it the wear model of sl/core/wear is used.

local M = {}

local strings = require('sl/core/strings')
local svc = require('sl/core/service')
local market = require('sl/core/market')
local wear = require('sl/core/wear')

local function opt(key, default) local v = sl_options and sl_options.get and tonumber((sl_options.get(key))) return v or default end
local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function carById(s, id) for _, c in ipairs(s.cars) do if c.id == id then return c end end end

local function workbench(s)
  if sl_career.visit and sl_career.visit() then return sl_rallyservice ~= nil and sl_rallyservice.atStall ~= nil and sl_rallyservice.atStall() == true end      -- (on a visit only a service stall is a bench)
  local f = sl_upgrades and sl_upgrades.features and sl_upgrades.features(s)
  return f == nil or f.workbench == true
end

-- Part Wear's parts for the car, or nil (not installed, off, not watched)
local function partwear(car)
  local pw = rawget(_G, 'slrr_partwear')
  if not pw then return nil end
  local vid
  local veh = sl_fleet and sl_fleet.vehicleOf and sl_fleet.vehicleOf(car.id)
  if veh then vid = veh:getID() end
  local ok, r = pcall(function()
    local x = vid and pw.conditionsOf and pw.conditionsOf(vid)
    if x == nil and pw.conditionsOfKey then x = pw.conditionsOfKey('slcar' .. tostring(car.id)) end
    return x
  end)
  return ok and type(r) == 'table' and r.parts or nil
end

-- the Wear rate setting now (Mods > Difficulty > Wear): 0.5, 1, 2 or 4
local function rate()
  return svc.rate(sl_options and sl_options.get and sl_options.get('slWearRate'))
end

local function figures(car)
  local c = sl_carcare.careOf(car)
  local k = rate()
  local sv = svc.state(car, c.engineKm, c.abuse, k)
  svc.sync(sv, k, c.engineKm, car.mileage, c.abuse)
  local gross = svc.gross(sv, c.engineKm, car.mileage, c.abuse)
  return c, sv, gross, svc.net(sv, gross)
end

-- the wear since you bought the car, less what overhauls put right (for the car report; nil with the part off)
function M.wearOf(car)
  local _, _, _, net = figures(car)
  return net
end

-- for the phone and the garage: one car's service card
function M.serviceOf(carId)
  local s = career()
  local car = s and carById(s, carId)
  if not car then return nil end
  local c, sv, _, net = figures(car)
  local km = svc.since(sv, c.engineKm, car.mileage)
  local bench = workbench(s)
  local pf = (opt('slServicePrice', 100) / 100) * (sl_perks and sl_perks.factor('service') or 1) * (sl_mastery and sl_mastery.factor('service', car) or 1) * (sl_mates and sl_mates.labourFactor and sl_mates.labourFactor() or 1)      -- (tier perks, the car's mastery, a mechanic mate)
  local note = bench and '' or strings.t('service.no_bench')
  local basicCost = math.floor(svc.basicCost(car.value, bench) * pf / 10 + 0.5) * 10
  local fullCost = math.floor(svc.overhaulCost(car.value, net, market.REPAIR_CONDITION, bench) * pf / 10 + 0.5) * 10
  local fullNote = fullCost == basicCost and (note ~= '' and (note .. ' ') or '') .. strings.t('service.full_same') or note          -- (nothing is worn: the overhaul adds nothing to the basic service)
  local rc = market.REPAIR_CONDITION
  return { due = svc.due(sv, km), km_since = math.floor(km), km_interval = math.floor(svc.INTERVAL / rate()), wearFactor = svc.wearFactor(sv, km), count = sv.count,
    sections = svc.sections(net, partwear(car)),
    options = {
      { id = 'basic', label = strings.t('service.basic'), cost = basicCost, available = true, why = note },
      { id = 'full', label = strings.t('service.overhaul'), cost = fullCost, available = true, why = fullNote },
    } }
end

-- pay for a service: option 'basic' or 'full'. Returns ok, text.
function M.service(carId, optionId, factor)      -- factor: the price times this (0: the caller has charged already, the independent mechanic); nil = the price as it is
  local s = career()
  local car = s and carById(s, tonumber(carId))
  if not car then return false, strings.t('service.no_car') end
  local info = M.serviceOf(car.id)
  local opt
  for _, o in ipairs(info.options) do if o.id == optionId then opt = o end end
  if not opt then return false, strings.t('service.no_such_service') end
  local cost = math.floor(opt.cost * (tonumber(factor) or 1) + 0.5)
  if cost > 0 and not sl_career.addMoney(-cost, opt.label) then return false, strings.t('career.not_enough_money') end
  local c, sv = figures(car)
  if optionId == 'full' then svc.doOverhaul(sv, c.engineKm, car.mileage, c.abuse) else svc.doBasic(sv, c.engineKm, car.mileage) end
  sl_carcare.note(car, strings.t('service.noted', opt.label))
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('service.done', opt.label, cost)
end

-- the same factor to Part Wear (setWearRate) and the CSFX tyres (setWearScale), when they are there and have the call; sent at the start, on a change, and again every few seconds
-- until both took it (they may load later). Part off: nothing is sent.
local sent = {}
local function push()
  if not require('sl/core/features').on('service') then return end
  local k = rate()
  for _, t in ipairs({ { 'slrr_partwear', 'setWearRate', 'getWearRate' }, { 'carSurfaceFx_tyres', 'setWearScale', 'getWearScale' } }) do
    local mod = rawget(_G, t[1])
    if mod and type(mod[t[2]]) == 'function' then
      local okG, now = true, nil
      if type(mod[t[3]]) == 'function' then okG, now = pcall(mod[t[3]]) end          -- (a module that was reloaded starts at 1 again: ask)
      if sent[t[1]] ~= k or (okG and now ~= nil and now ~= k) then
        if pcall(mod[t[2]], k) then sent[t[1]] = k end
      end
    end
  end
end
-- a record for every car of the career as soon as the part is on (at the career start, a purchase, the switch turned on), so the origin of the 40x wear is when the part began to watch the
-- car and not whenever the phone first asked
local function ensureAll()
  local s = career()
  if not s then return end
  local k = rate()
  for _, car in ipairs(s.cars) do
    local c = sl_carcare.careOf(car)
    svc.sync(svc.state(car, c.engineKm, c.abuse, k), k, c.engineKm, car.mileage, c.abuse)
  end
end

local timer = 0
function M.onUpdate(dt)
  timer = timer + (dt or 0)
  if timer < 5 then return end
  timer = 0
  push()
  ensureAll()
end
function M.onStreetLegalStarted() svc.INTERVAL = opt('slServiceKm', svc.INTERVAL) sent = {} push() ensureAll() end
function M.onStreetLegalOption(key, value)
  if key == 'slWearRate' then sent = {} push() ensureAll() end
  if key == 'slService' and value == true then ensureAll() end
  if key == 'slServiceKm' then svc.INTERVAL = tonumber(value) or svc.INTERVAL sent = {} push() end
end
function M.onClientEndMission() sent = {} end

require('sl/core/features').gate('service', M, nil, nil, { 'wearOf', 'serviceOf', 'service' })

return M
