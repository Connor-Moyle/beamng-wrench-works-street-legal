-- Street Legal: fuel siphoning (docs/FUEL_SIPHON.md). Pure rules, no game calls: tested by tools/luatest.js. The game side is sl/siphon.lua.
-- Energy and litres of the game fuel tanks (lua/vehicle/energyStorage/fuelTank.lua: density x energy density), what moves in one step between a tank and a can, what a can may take,
-- when a siphon is interrupted and how risky it is.

local M = {}

-- J per litre by energy type: density (kg/L) x energy density (J/kg) as the game fuel tank sets them
M.JOULES_PER_L = { gasoline = 0.75 * 41.5e6, diesel = 0.84 * 43e6, kerosene = 0.80 * 43e6 }
M.FLOOR = 0.02            -- a siphoned tank keeps this share of its capacity
M.REACH = 2.5             -- m from the car at which the prompt shows
M.LET_GO = 4              -- m from the car beyond which a siphon stops
M.RATE = 0.25             -- L/s (the setting siphonRate)

local function num(v, d) v = tonumber(v) if v and v == v and v > -math.huge and v < math.huge then return v end return d end

-- one tank of the game list ({ name, storageType, energyType, currentEnergy, maxEnergy }): { fuel, litres, capacity, name } or nil for a tank that is not liquid fuel
function M.fuelOf(tank)
  if type(tank) ~= 'table' then return nil end
  local per = M.JOULES_PER_L[tank.energyType]
  if not per or (tank.storageType ~= nil and tank.storageType ~= 'fuelTank') then return nil end
  local cap = math.max(0, num(tank.maxEnergy, 0))
  if cap <= 0 then return nil end
  return { fuel = tank.energyType, litres = math.max(0, math.min(cap, num(tank.currentEnergy, 0))) / per, capacity = cap / per, name = tank.name }
end

-- the first siphonable tank of a car list
function M.pick(tanks)
  for _, t in ipairs(type(tanks) == 'table' and tanks or {}) do
    local f = M.fuelOf(t)
    if f then return f end
  end
  return nil
end

function M.joules(fuel, litres) return (M.JOULES_PER_L[fuel] or 0) * math.max(0, num(litres, 0)) end

-- can = { litres, size, fuel (nil when empty) }; tank = the fuelOf() table. May the can take fuel from the tank? (the type must match a non-empty can)
function M.canTake(can, tank)
  if type(can) ~= 'table' or type(tank) ~= 'table' then return false end
  if num(can.litres, 0) >= num(can.size, 0) then return false end
  return num(can.litres, 0) <= 0 or can.fuel == nil or can.fuel == tank.fuel
end

-- may the can be poured into the tank? the same type (a petrol tank refuses diesel), litres in the can and room in the tank
function M.canPour(can, tank)
  if type(can) ~= 'table' or type(tank) ~= 'table' or num(can.litres, 0) <= 0 then return false end
  return can.fuel == tank.fuel and tank.litres < tank.capacity - 1e-9
end

-- litres moving from the tank into the can in dt seconds: bounded by the rate, the room in the can and the tank level over the floor; never negative
function M.take(can, tank, dt, rate)
  if not M.canTake(can, tank) then return 0 end
  local room = num(can.size, 0) - num(can.litres, 0)
  local avail = tank.litres - M.FLOOR * tank.capacity
  return math.max(0, math.min(num(rate, M.RATE) * math.max(0, num(dt, 0)), room, avail))
end

-- litres moving from the can into the tank in dt seconds
function M.pour(can, tank, dt, rate)
  if not M.canPour(can, tank) then return 0 end
  return math.max(0, math.min(num(rate, M.RATE * 4) * math.max(0, num(dt, 0)), num(can.litres, 0), tank.capacity - tank.litres))
end

-- state = { held (the button), dist (m), inCar, carSpeed (m/s), tankGone }
function M.interrupted(state)
  state = type(state) == 'table' and state or {}
  return not state.held or num(state.dist, math.huge) > M.LET_GO or state.inCar == true or num(state.carSpeed, 0) > 1 or state.tankGone == true
end

-- the risk of being noticed per 10 seconds of siphoning: the setting x the base (night 0.10, day 0.25) x (1 + 0.5 per witness) x 2 within sight of police; capped at 1
function M.risk(night, witnesses, police, setting)
  local r = num(setting, 1) * (night and 0.10 or 0.25) * (1 + 0.5 * math.max(0, num(witnesses, 0))) * (police and 2 or 1)
  return math.max(0, math.min(1, r))
end

-- the chance of being noticed over dt seconds
function M.noticed(risk10, dt) return 1 - (1 - math.max(0, math.min(1, num(risk10, 0)))) ^ (math.max(0, num(dt, 0)) / 10) end

return M
