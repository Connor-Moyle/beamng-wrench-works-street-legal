-- Street Legal Racing: looking after your cars (extension name: sl_carcare)
-- Every car you own keeps, in the save: its 12 V battery, the engine's kilometres (wear) and the
-- oil's (since the last change), the fuel grade in the tank, its oil / coolant / fuel / nitrous
-- levels, the game's own part conditions (so a crash stays a crash, and a worn part stays worn),
-- what is in its trunk, and its history (owners, races, wins, wrecks). The car's side is the
-- vehicle extension slCar; the rules are lua/common/sl_carcare.lua.

local M = {}

local rules = require('sl_carcare')

local attached = {}          -- vehicle id -> car id, once slCar is in it and set up
local timer, condTimer = 0, 0
local lastDamage = {}         -- vehicle id -> the damage it last reported
local CRASH_DAMAGE = 2000     -- this much more since the last report (2 s) is a crash
local settleUntil = {}        -- vehicle id -> clock: its saved dents are still going back on until then

local ASK_CONDITIONS = [[obj:queueGameEngineLua(string.format('if sl_carcare then sl_carcare.onConditions(%d,%s) end', obj:getId(), serialize(partCondition.getConditions())))]]

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local function carById(s, id)
  for _, c in ipairs(s and s.cars or {}) do if c.id == id then return c end end
end

-- a car's care record, made on first sight: a used car comes with used oil and a tired battery
function M.careOf(car)
  if not car.care then
    local km = tonumber(car.mileage) or 0
    local seed = (car.id or 1) * 7919 + math.floor(km)
    car.care = {
      battery = 0.55 + (seed % 45) / 100,
      engineKm = km, oilKm = km > 1000 and (seed % 14000) or 0,
      fuel = 'regular', trunk = {},
    }
  end
  car.care.trunk = car.care.trunk or {}
  car.history = car.history or { owners = (tonumber(car.mileage) or 0) > 1000 and (1 + (car.id or 1) % 3) or 0, races = 0, wins = 0, wrecks = 0, log = {} }
  return car.care
end

function M.historyOf(car)
  M.careOf(car)
  return car.history
end

-- something worth remembering about a car (kept short: the last 20)
function M.note(car, text)
  local h = M.historyOf(car)
  local s = career()
  h.log[#h.log + 1] = { day = s and s.day or 0, text = text }
  while #h.log > 20 do table.remove(h.log, 1) end
end

local function attach(vid, car)
  local veh = getObjectByID(vid)
  if not veh then return end
  local c = M.careOf(car)
  attached[vid] = car.id
  settleUntil[vid] = os.clock() + 10
  veh:queueLuaCommand('extensions.load("slCar")')
  -- the part conditions first (wear, damage, fluids the game keeps), then our numbers on top
  if car.conditions then
    veh:queueLuaCommand('partCondition.initConditions(' .. serialize(car.conditions) .. ')')
  else
    veh:queueLuaCommand(string.format('partCondition.initConditions(nil, %d, 1, 1)', math.floor((c.engineKm or 0) * 1000)))
  end
  veh:queueLuaCommand('if slCar then slCar.setState(' .. serialize({ battery = c.battery, engineKm = c.engineKm, oilKm = c.oilKm, fuel = c.fuel,
    oilLevel = c.oilLevel, coolantLevel = c.coolantLevel, fuelLevel = c.fuelLevel, n2o = c.n2o }) .. ') end')
  -- the driver chosen for this car in the garage (SLRR Drivers mod), back in the seat
  -- (none chosen yet: the mod's default, also for a car bought straight off a lot, where the seats are empty)
  if slrrDrivers and slrrDrivers.setDriver then
    local d = car.driver or (slrrDrivers.getDefaultDriver and slrrDrivers.getDefaultDriver())
    slrrDrivers.setDriver(vid, d ~= 'none' and d or nil)
  end
end

-- the car reports every few seconds
function M.onReport(vid, t)
  local s = career()
  local carId = attached[vid]
  local car = s and carId and carById(s, carId)
  if not car or type(t) ~= 'table' then return end
  local c = M.careOf(car)
  for _, k in ipairs({ 'battery', 'oilLevel', 'coolantLevel', 'fuelLevel', 'n2o', 'engineKm', 'oilKm', 'fuel', 'factor', 'coolantTemp', 'fuelLitres', 'fuelCapacity' }) do
    if t[k] ~= nil then c[k] = t[k] end
  end
  -- a crash: its dents and the parts it broke go into the save now, not at the next minute's look
  -- (quitting straight after would lose them). Not in a garage: it measures the car itself there.
  if type(t.damage) == 'number' then
    local before = lastDamage[vid]
    lastDamage[vid] = t.damage
    local phase = slrr_garage and slrr_garage.getPhase and slrr_garage.getPhase()
    if before and t.damage - before > CRASH_DAMAGE and (not phase or phase == 'idle') and os.clock() > (settleUntil[vid] or 0) then
      local veh = getObjectByID(vid)
      if veh then
        veh:queueLuaCommand('extensions.load("slrrGarageVeh") if slrrGarageVeh then slrrGarageVeh.capture() end')
        veh:queueLuaCommand(ASK_CONDITIONS)
      end
    end
  end
end

-- the game's own part conditions, asked for now and then and kept with the car
function M.onConditions(vid, conditions)
  local s = career()
  local carId = attached[vid]
  local car = s and carId and carById(s, carId)
  if car and type(conditions) == 'table' then car.conditions = conditions end
end

local function askConditions()
  for vid in pairs(attached) do
    local veh = getObjectByID(vid)
    if veh then veh:queueLuaCommand(ASK_CONDITIONS) else attached[vid] = nil end
  end
end

function M.onStreetLegalBeforeSave() askConditions() end

-- one car, now (it is about to be put away): its answer comes a frame or two later
function M.askConditions(vid)
  local veh = attached[vid] and getObjectByID(vid)
  if veh then veh:queueLuaCommand(ASK_CONDITIONS) end
end

-- a respawned car (the garage rebuilding it) has fresh Lua: set it up again
function M.onVehicleSpawned(vid) attached[vid] = nil lastDamage[vid] = nil end
function M.onVehicleDestroyed(vid) attached[vid] = nil lastDamage[vid] = nil end

function M.onUpdate(dtReal)
  local s = career()
  if not s then return end
  timer, condTimer = timer + dtReal, condTimer + dtReal
  if timer > 1 then
    timer = 0
    for _, car in ipairs(s.cars) do
      local vid = sl_fleet and sl_fleet.vehicleOf(car.id)
      if vid then
        local id = type(vid) == 'number' and vid or vid:getID()
        if attached[id] ~= car.id then attach(id, car) end
      end
    end
  end
  if condTimer > 30 then condTimer = 0 askConditions() end
end

----------------------------------------------------------------------------------------------
-- what you can do with a car: top it up, use what is in the trunk

local function vehicleOfCar(carId)
  local v = sl_fleet and sl_fleet.vehicleOf(carId)
  if type(v) == 'number' then v = getObjectByID(v) end
  return v
end

-- kind: 'oil' | 'coolant' | 'battery' | 'fuel' | 'n2o'; amount in litres; fuelId for fuel
function M.refill(carId, kind, amount, fuelId)
  local s = career()
  local car = s and carById(s, carId)
  local veh = vehicleOfCar(carId)
  if not car or not veh then return false, 'That car is not here.' end
  local c = M.careOf(car)
  if kind == 'battery' then c.battery = 1 end
  if kind == 'fuel' and fuelId then c.fuel = fuelId end
  veh:queueLuaCommand(string.format('if slCar then slCar.refill(%q, %s, %s) end', kind, tostring(amount or 0), fuelId and string.format('%q', fuelId) or 'nil'))
  return true
end

-- use one thing from the car's trunk on it (you need to be at the car)
local USE = { oil = { 'oil', 4 }, coolant = { 'coolant', 5 }, battery = { 'battery', 0 }, fuelCan = { 'fuel', 20 } }
function M.useItem(carId, itemId)
  local s = career()
  local car = s and carById(s, carId)
  if not car then return false, 'No such car.' end
  local veh, player = vehicleOfCar(carId), getPlayerVehicle(0)
  if not veh or not player or (veh:getID() ~= player:getID() and (veh:getPosition() - player:getPosition()):length() > 6) then
    return false, 'Go to the car first.'
  end
  local c = M.careOf(car)
  if not rules.trunkTake(c.trunk, itemId) then return false, 'There is none in the trunk.' end
  local use = USE[itemId]
  M.refill(carId, use[1], use[2], itemId == 'fuelCan' and (c.canFuel or c.fuel) or nil)
  extensions.hook('onStreetLegalChanged')
  return true, ({ oil = 'Oil topped up.', coolant = 'Coolant topped up.', battery = 'New battery in.', fuelCan = 'The can went in the tank.' })[itemId]
end

-- buy something into a car's trunk (at a gas station or the garage)
function M.buyItem(carId, itemId)
  local s = career()
  local car = s and carById(s, carId)
  local item = rules.ITEMS[itemId]
  if not car or not item then return false, 'Nothing to buy.' end
  local c = M.careOf(car)
  if #c.trunk >= rules.TRUNK_SLOTS then return false, 'The trunk is full.' end
  if not sl_career.addMoney(-item.price, 'Bought: ' .. item.name) then return false, string.format('It is $%d. You have $%d.', item.price, s.money) end
  rules.trunkAdd(c.trunk, itemId)
  extensions.hook('onStreetLegalChanged')
  return true, item.name .. ' in the trunk.'
end

-- what the phone shows of a car
function M.summary(car)
  local c = M.careOf(car)
  return {
    battery = c.battery, oilLevel = c.oilLevel, coolantLevel = c.coolantLevel, fuelLevel = c.fuelLevel, n2o = c.n2o,
    engineKm = math.floor(c.engineKm or 0), oilKm = math.floor(c.oilKm or 0), fuel = rules.fuel(c.fuel).name,
    performance = rules.performance({ engineKm = c.engineKm, oilKm = c.oilKm, oilLevel = c.oilLevel or 1, fuel = c.fuel }),
    trunk = c.trunk, history = M.historyOf(car),
  }
end

-- the car you raced in remembers it
function M.onStreetLegalRaceResult(won, opponent)
  local car = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  if not car then return end
  local h = M.historyOf(car)
  h.races = (h.races or 0) + 1
  if won then h.wins = (h.wins or 0) + 1 end
  M.note(car, (won and 'Beat ' or 'Lost to ') .. tostring(opponent or 'a racer'))
end

-- a big hit (the garage's damage report says how bad the body is): a wreck in its history
function M.onWrenchWorksDamage(vid, data)
  local s = career()
  local carId = attached[vid]
  local car = s and carId and carById(s, carId)
  if not car or type(data) ~= 'table' then return end
  local beams = #(data.beams or {})
  local h = M.historyOf(car)
  if beams > 400 and not h.wreckedNow then
    h.wreckedNow = true
    h.wrecks = (h.wrecks or 0) + 1
    M.note(car, 'Wrecked')
  elseif beams < 50 then
    h.wreckedNow = nil
  end
end

function M.onClientEndMission() attached = {} end
function M.onStreetLegalStopped() attached = {} end

return M
