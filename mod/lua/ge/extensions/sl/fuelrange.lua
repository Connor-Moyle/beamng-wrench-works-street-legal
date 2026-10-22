-- Street Legal: fuel range and low-fuel warnings (extension name: sl_fuelrange; campaign expansion #9, the control repo's docs/FUEL_RANGE.md). The game burns the fuel; this watches the drop of the
-- tank's litres over the kilometres slCar reports (sl_carcare.onReport hands every report here) and tells the player: a range on the HUD, a toast at low, critical and empty with the nearest station,
-- the fuel can in the trunk as the way out, the tow when the car has stopped, the station price in the Map app. Rules: sl/core/range. Switch: slFuelRange (off by default; off does nothing at all).

local M = {}

local strings = require('sl/core/strings')
local R = require('sl/core/range')
local carRules = require('sl_carcare')

local tracks, told, shown = {}, {}, {}          -- vehicle id -> the car's track / the level last told / { range (display km), level, litres }

local function on() return sl_options ~= nil and sl_options.get ~= nil and sl_options.get('slFuelRange') == true end
local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) if text then guihooks.trigger('slPhoneToast', { text = text }) end if ui_message then ui_message(text, 6, 'streetLegal') end end

-- the nearest gas station to a point: its name and the distance in metres, or nil
function M.nearestGas(pos)
  if not (pos and sl_career and sl_career.allPlaces) then return nil end
  local best, bestD
  for _, p in pairs(sl_career.allPlaces() or {}) do
    if p.kind == 'gas' and p.pos then
      local d = math.sqrt((p.pos.x - pos.x) ^ 2 + (p.pos.y - pos.y) ^ 2)
      if not bestD or d < bestD then best, bestD = p, d end
    end
  end
  if best then return best.name or best.id, bestD end
end

local function nearestText(veh)
  local ok, pos = pcall(function() return veh:getPosition() end)
  if not (ok and pos) then return '' end
  local name, d = M.nearestGas(pos)
  if not name then return '' end
  return ' ' .. strings.t('fuel.nearest', name, string.format('%.1f', d / 1000))
end

local function hasCan(vid)
  local car = sl_fleet and sl_fleet.carOfVehicle and sl_fleet.carOfVehicle(vid)
  local s = career()
  if not (car and s) then return false end
  for _, c in ipairs(s.cars) do
    if c.id == car then
      local care = sl_carcare and sl_carcare.careOf and sl_carcare.careOf(c)
      for _, id in ipairs(care and care.trunk or {}) do if id == 'fuelCan' then return true end end
    end
  end
  return false
end

local function announce(vid, level, rangeKm)
  local me = getPlayerVehicle and getPlayerVehicle(0)
  if not (me and me:getID() == vid) then return end            -- (only the car you drive talks)
  local km = R.display(rangeKm) or 0
  local can = hasCan(vid) and (' ' .. strings.t('fuel.can_hint')) or ''
  if level == 'low' then toast(strings.t('fuel.low', km) .. nearestText(me))
  elseif level == 'critical' then toast(strings.t('fuel.critical', km) .. nearestText(me) .. can)
  elseif level == 'empty' then toast(strings.t('fuel.empty') .. can) end
end

-- a report of slCar (through sl_carcare.onReport): { fuelLitres, fuelCapacity, fuelLevel, engineKm }
function M.onReport(vid, t)
  if not on() or not career() or type(t) ~= 'table' then return end
  if type(t.fuelLitres) ~= 'number' or type(t.engineKm) ~= 'number' then return end          -- (a car with no fuel tank reports none)
  local track = tracks[vid]
  if not track then track = R.newTrack() tracks[vid] = track end
  R.push(track, t.engineKm, t.fuelLitres)
  local perKm = R.consumption(track)
  local range = R.range(t.fuelLitres, perKm)
  local frac = type(t.fuelLevel) == 'number' and t.fuelLevel or (t.fuelCapacity and t.fuelCapacity > 0 and t.fuelLitres / t.fuelCapacity) or nil
  local level = R.level(frac, t.fuelLitres, range)
  shown[vid] = { range = R.display(range), level = level, litres = t.fuelLitres }
  if level == 'ok' then told[vid] = nil
  elseif R.worse(level, told[vid]) then told[vid] = level announce(vid, level, range or 0) end
end

-- for the HUD (sl/hud): { range = km, level } for this vehicle, or nil (switch off, nothing reported)
function M.hud(vid)
  if not on() then return nil end
  local s = shown[vid]
  if not (s and s.range) then return nil end
  return { range = s.range, level = s.level }
end

-- for the Map app: when the car you drive is low, a line with the nearest station
function M.mapNote(pos)
  if not on() then return nil end
  local me = getPlayerVehicle and getPlayerVehicle(0)
  local s = me and shown[me:getID()]
  if not (s and s.level ~= 'ok') then return nil end
  local name, d = M.nearestGas(pos)
  if not name then return nil end
  return strings.t('fuel.map_note', s.range or 0, name, string.format('%.1f', d / 1000))
end

-- the price a map entry shows for a gas station: the base price of the cheapest grade (the pump scales it)
function M.priceText()
  if not on() then return nil end
  return strings.t('fuel.price', string.format('%.2f', carRules.FUELS[1].pricePerLitre))
end

function M.onVehicleDestroyed(vid) tracks[vid], told[vid], shown[vid] = nil, nil, nil end
function M.onStreetLegalStopped() tracks, told, shown = {}, {}, {} end
function M.onClientEndMission() tracks, told, shown = {}, {}, {} end

function M.status() return { on = on(), shown = shown } end

return M
