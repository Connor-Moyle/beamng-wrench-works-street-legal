-- Street Legal: servicing (extension name: sl_service; career expansion #2). Rules in sl/core/service. A service every ~150 km keeps the wear down; skipping it makes it faster.
-- With Part Wear installed, its per-part conditions are read (slrr_partwear.conditionsOf / conditionsOfKey, read-only) and shown per section; without it the wear model of sl/core/wear is used.

local M = {}

local strings = require('sl/core/strings')
local svc = require('sl/core/service')
local market = require('sl/core/market')
local wear = require('sl/core/wear')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function carById(s, id) for _, c in ipairs(s.cars) do if c.id == id then return c end end end

local function workbench(s)
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

local function figures(car)
  local c = sl_carcare.careOf(car)
  local sv = svc.state(car)
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
  local note = bench and '' or strings.t('service.no_bench')
  local rc = market.REPAIR_CONDITION
  return { due = svc.due(km), km_since = math.floor(km), km_interval = svc.INTERVAL, wearFactor = svc.wearFactor(km), count = sv.count,
    sections = svc.sections(net, partwear(car)),
    options = {
      { id = 'basic', label = strings.t('service.basic'), cost = svc.basicCost(car.value, bench), available = true, why = note },
      { id = 'full', label = strings.t('service.overhaul'), cost = svc.overhaulCost(car.value, net, rc, bench), available = true, why = note },
    } }
end

-- pay for a service: option 'basic' or 'full'. Returns ok, text.
function M.service(carId, optionId)
  local s = career()
  local car = s and carById(s, tonumber(carId))
  if not car then return false, strings.t('service.no_car') end
  local info = M.serviceOf(car.id)
  local opt
  for _, o in ipairs(info.options) do if o.id == optionId then opt = o end end
  if not opt then return false, strings.t('service.no_such_service') end
  if not sl_career.addMoney(-opt.cost, opt.label) then return false, strings.t('career.not_enough_money') end
  local c, sv = figures(car)
  if optionId == 'full' then svc.doOverhaul(sv, c.engineKm, car.mileage, c.abuse) else svc.doBasic(sv, c.engineKm, car.mileage) end
  sl_carcare.note(car, strings.t('service.noted', opt.label))
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('service.done', opt.label, opt.cost)
end

require('sl/core/features').gate('service', M, nil, nil, { 'wearOf', 'serviceOf', 'service' })

return M
