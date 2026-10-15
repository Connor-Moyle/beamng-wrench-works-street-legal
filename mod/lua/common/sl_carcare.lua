-- Street Legal Racing: the rules of looking after a car. Shared by the career (sl_carcare) and the
-- car's own Lua (slCar), so it lives in lua/common. Pure: no game calls (tested by tools/luatest.js).

local M = {}

-- fuel grades: a little more power for the better ones, at a price (SLRR sold grades too)
M.FUELS = {
  { id = 'regular', name = 'Regular 91', octane = 91, pricePerLitre = 1.45, torque = 0.97 },
  { id = 'premium', name = 'Premium 95', octane = 95, pricePerLitre = 1.65, torque = 1.00 },
  { id = 'super', name = 'Super 98', octane = 98, pricePerLitre = 1.85, torque = 1.02 },
  { id = 'race', name = 'Race 102', octane = 102, pricePerLitre = 3.20, torque = 1.04 },
}
local byId = {}
for _, f in ipairs(M.FUELS) do byId[f.id] = f end
function M.fuel(id) return byId[id] or byId.premium end

-- what goes in the trunk
M.ITEMS = {
  fuelCan = { name = 'Fuel can (20 L)', price = 25, litres = 20 },
  oil = { name = 'Engine oil (4 L)', price = 45, litres = 4 },
  coolant = { name = 'Coolant (5 L)', price = 30, litres = 5 },
  battery = { name = '12 V battery', price = 120 },
}
M.TRUNK_SLOTS = 6

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function lerpDown(x, x0, x1, y0, y1) -- y0 at x0 falling to y1 at x1, flat outside
  if x <= x0 then return y0 end
  if x >= x1 then return y1 end
  return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
end

-- an engine wears: full power to 50,000 km, 12 % less by 350,000 (until it is rebuilt)
function M.wearFactor(engineKm) return lerpDown(math.max(0, engineKm or 0), 50000, 350000, 1, 0.88) end
-- oil gets old: fine for 8,000 km, 5 % down by 25,000
function M.oilAgeFactor(oilKm) return lerpDown(math.max(0, oilKm or 0), 8000, 25000, 1, 0.95) end
-- and low oil costs a little before it costs the engine
function M.oilLevelFactor(level)
  if level == nil then return 1 end
  level = clamp(level, 0, 1)
  if level >= 0.6 then return 1 end
  return 0.9 + 0.1 * level / 0.6
end

-- all of it together: the engine's torque multiplier
function M.performance(state)
  state = state or {}
  local x = M.wearFactor(state.engineKm) * M.oilAgeFactor(state.oilKm) * M.oilLevelFactor(state.oilLevel) * M.fuel(state.fuel).torque
  return math.floor(x * 1000 + 0.5) / 1000
end

-- a worn engine loses oil: none below 150,000 km, more as it wears (litres per km)
function M.leakLitresPerKm(engineKm)
  engineKm = engineKm or 0
  if engineKm < 150000 then return 0 end
  return math.min(0.004, 0.0002 + (engineKm - 150000) / 200000 * 0.002)
end

-- the 12 V battery (0..1): the ignition and the lights drain it, the engine charges it
M.BATTERY_DRAIN = 1 / 2400
M.BATTERY_LIGHTS = 1 / 1200
M.BATTERY_CHARGE = 1 / 600
function M.battery(charge, dt, ignitionOn, engineRunning, lightsOn)
  charge = charge or 1
  dt = dt or 0
  if engineRunning then
    charge = charge + M.BATTERY_CHARGE * dt
  elseif ignitionOn then
    charge = charge - (M.BATTERY_DRAIN + (lightsOn and M.BATTERY_LIGHTS or 0)) * dt
  elseif lightsOn then
    charge = charge - M.BATTERY_LIGHTS * dt
  end
  return clamp(charge, 0, 1)
end
function M.canStart(charge) return charge == nil or charge >= 0.15 end

-- the trunk: a list of item ids
function M.trunkAdd(trunk, itemId)
  if not M.ITEMS[itemId] then return false, 'Unknown item.' end
  if #trunk >= M.TRUNK_SLOTS then return false, 'The trunk is full.' end
  trunk[#trunk + 1] = itemId
  return true
end
function M.trunkTake(trunk, itemId)
  for i, v in ipairs(trunk) do
    if v == itemId then table.remove(trunk, i) return true end
  end
  return false
end
function M.trunkCount(trunk, itemId)
  local n = 0
  for _, v in ipairs(trunk) do if v == itemId then n = n + 1 end end
  return n
end

function M.oilChangeCost(litresCapacity) return math.floor(25 + 12 * (litresCapacity or 5) + 0.5) end
function M.fillCost(fuelId, litres) return math.floor(M.fuel(fuelId).pricePerLitre * (litres or 0) * 100 + 0.5) / 100 end

return M
