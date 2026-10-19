-- Street Legal Racing: what the career adds to a car, in the car's own Lua (vehicle extension slCar)
-- A 12 V battery that the ignition drains and the engine charges (flat: it will not crank); the
-- engine's oil and coolant, read from and topped up in the game's own engine model; a worn engine,
-- old oil and the fuel grade taking a little of the power; worn engines (high mileage) losing oil
-- on the road, leaving drops behind (with the Enhanced Skidmarks mod). The rules are in
-- lua/common/sl_carcare.lua; the career (lua/ge/extensions/sl/carcare.lua) keeps the numbers.

local M = {}

local rules = require('sl_carcare')

local state = { battery = 1, engineKm = 0, oilKm = 0, fuel = 'premium', abuse = { engine = 0, brakes = 0, drive = 0, susp = 0 } }
local prevSpeed, abuseTimer, lastDamage = 0, 0, nil
local engine, oil, coolant
local factor = 1
local lastPos
local reportTimer, capTimer, dripTimer = 0, 0, 0
local leakCarry = 0
local flatWarned = false

-- the engine model keeps its oil and coolant in a table of its own: found through one of its functions
local function findFluids()
  engine = powertrain and powertrain.getDevice and powertrain.getDevice('mainEngine')
  oil, coolant = nil, nil
  local f = engine and engine.thermals and engine.thermals.getPartConditionRadiator
  if not f or not debug or not debug.getupvalue then return end
  for i = 1, 40 do
    local okU, name, value = pcall(debug.getupvalue, f, i)       -- a sandboxed build must not throw every call
    if not okU or not name then break end
    if name == 'fluidReservoirs' and type(value) == 'table' then oil, coolant = value.oil, value.coolant end
  end
end

local function level(res) return res and res.initialMass and res.initialMass > 0 and res.currentMass / res.initialMass or nil end
local function setLevel(res, v)
  if res and res.initialMass and res.initialMass > 0 then res.currentMass = math.max(0, math.min(1, v)) * res.initialMass end
end

local function applyFactor()
  factor = rules.performance({ engineKm = state.engineKm, oilKm = state.oilKm, oilLevel = level(oil) or 1, fuel = state.fuel })
  if engine and engine.outputTorqueState and engine.outputTorqueState > factor then engine.outputTorqueState = factor end
end

-- from the career: { battery, engineKm, oilKm, fuel, oilLevel, coolantLevel }
function M.setState(s)
  if type(s) ~= 'table' then return end
  for k, v in pairs(s) do state[k] = v end
  findFluids()
  if s.oilLevel then setLevel(oil, s.oilLevel) end
  if s.coolantLevel then setLevel(coolant, s.coolantLevel) end
  -- the tank and the nitrous bottle as they were left (a respawned car starts full otherwise)
  if s.fuelLevel then
    local tank = M.fuelTank()
    if tank then tank:setRemainingVolume(M.litres(tank) * math.max(0, math.min(1, s.fuelLevel))) end
  end
  if s.n2o then
    for _, tank in pairs(energyStorage.getStorages() or {}) do
      if tank.type == 'n2oTank' and tank.setRemainingRatio then tank:setRemainingRatio(math.max(0, math.min(1, s.n2o))) end
    end
  end
  applyFactor()
end

-- topping up: kind 'oil' | 'coolant' (litres), 'battery' (a new one), 'fuel' (litres of fuel id)
function M.refill(kind, amount, fuelId)
  if kind == 'battery' then
    state.battery = 1
  elseif kind == 'oil' and oil then
    local capacity = math.max(1, (oil.initialMass or 4) / 0.88)          -- litres, from kg
    setLevel(oil, (level(oil) or 1) + (amount or 0) / capacity)
  elseif kind == 'coolant' and coolant then
    local capacity = math.max(1, coolant.initialMass or 6)
    setLevel(coolant, (level(coolant) or 1) + (amount or 0) / capacity)
  elseif kind == 'fuel' then
    local tank = M.fuelTank()
    if tank then
      local cap = M.litres(tank)
      tank:setRemainingVolume(math.min(cap, (tank.remainingVolume or 0) + (amount or 0)))
    end
    if fuelId then state.fuel = fuelId end
  elseif kind == 'n2o' then
    for _, tank in pairs(energyStorage.getStorages() or {}) do
      if tank.type == 'n2oTank' and tank.setRemainingRatio then tank:setRemainingRatio(1) end
    end
  end
  applyFactor()
  M.report()
end

-- the (first) fuel tank, and how many litres it holds
function M.fuelTank()
  for _, tank in pairs(energyStorage and energyStorage.getStorages and energyStorage.getStorages() or {}) do
    if tank.type == 'fuelTank' and tank.setRemainingVolume and (tank.energyCapacity or 0) > 0 then return tank end
  end
end
function M.litres(tank)
  local per = (tank.fuelLiquidDensity or 0.75) * (tank.energyDensity or 41.5e6)
  return per > 0 and tank.energyCapacity / per or 0
end

-- the garage rebuilds the engine: its wear, its internal damage and its fluids, nothing else on the car
function M.rebuildEngine()
  findFluids()
  if engine then
    -- the engine's own part condition, fresh, keeps every other part as it is
    local conditions = partCondition and partCondition.getConditions and partCondition.getConditions()
    if type(conditions) == 'table' then
      for partId, cond in pairs(conditions) do
        if type(partId) == 'string' and partId:lower():find('engine', 1, true) and not partId:lower():find('mount', 1, true) then
          cond.odometer, cond.integrityValue, cond.integrityState = 0, 1, nil
        end
      end
      pcall(partCondition.initConditions, conditions)
    end
    -- the game's own engine reset (damage, flooding, thermals) wants the engine's jbeam section
    -- (built as powertrain.init builds it: its powertrain row merged with its own section)
    local jb
    for _, row in pairs(v and v.data and v.data.powertrain or {}) do
      if type(row) == 'table' and row.name == engine.name then jb = tableMergeRecursive(deepcopy(row), v.data[engine.name] or {}) end
    end
    if engine.reset and jb and pcall(engine.reset, engine, jb) and engine.registerStorage then
      -- the reset forgets its fuel tanks, nitrous and battery: hand them back as the game does at spawn
      for name in pairs(energyStorage.getStorages() or {}) do pcall(engine.registerStorage, engine, name) end
    end
    -- what a seized engine keeps otherwise (combustionEngine lockUp/disable)
    engine.outputTorqueState, engine.outputAVState = 1, 1
    engine.isBroken, engine.isDisabled, engine.starterDisabled, engine.isStalled = false, false, false, false
    engine.floodLevel = 0
    if damageTracker then
      for _, k in ipairs({ 'engineDisabled', 'engineLockedUp', 'engineReducedTorque', 'engineHydrolocked', 'catastrophicOverrevDamage', 'mildOverrevDamage', 'catastrophicOverTorqueDamage', 'impactDamage' }) do
        damageTracker.setDamage('engine', k, false)
      end
      damageTracker.setDamage('powertrain', engine.name, false)
    end
    findFluids()
    setLevel(oil, 1)
    setLevel(coolant, 1)
  end
  state.engineKm, state.oilKm = 0, 0
  applyFactor()
  M.report()
  -- the career keeps the fresh conditions now, or a later restore would bring the old engine back
  local fresh = partCondition and partCondition.getConditions and partCondition.getConditions()
  if type(fresh) == 'table' then
    obj:queueGameEngineLua(string.format('if sl_carcare then sl_carcare.onConditions(%d,%s) end', obj:getId(), serialize(fresh)))
  end
end

local function storageRatio(kind)
  for _, tank in pairs(energyStorage and energyStorage.getStorages and energyStorage.getStorages() or {}) do
    if tank.type == kind then return tank.remainingRatio end
  end
end

function M.report()
  local t = {
    battery = state.battery, oilLevel = level(oil), coolantLevel = level(coolant), fuelLevel = storageRatio('fuelTank'),
    n2o = storageRatio('n2oTank'), engineKm = state.engineKm, oilKm = state.oilKm, fuel = state.fuel, factor = factor,
    coolantTemp = engine and engine.thermals and engine.thermals.coolantTemperature or nil, abuse = state.abuse,
    damage = beamstate and beamstate.damage or nil,                           -- a jump: a crash, kept at once
  }
  local tank = M.fuelTank()
  if tank then t.fuelLitres, t.fuelCapacity = tank.remainingVolume, M.litres(tank) end
  obj:queueGameEngineLua(string.format('if sl_carcare then sl_carcare.onReport(%d,%s) end', obj:getId(), serialize(t)))
end

local function drip(kind)
  local p = obj:getPosition()
  -- the drop falling (addDripFx), then its stain on the road (addDrip)
  obj:queueGameEngineLua(string.format('local m = dirtSkidManager if m and m.addDrip then if m.addDripFx then m.addDripFx(%.3f,%.3f,%.3f,%q) end m.addDrip(%.3f,%.3f,%.3f,%q) end',
    p.x, p.y, p.z, kind, p.x, p.y, p.z - 0.2, kind))
end

function M.updateGFX(dt)
  -- the 12 V system
  local ign = electrics.values.ignitionLevel or 0
  local running = (electrics.values.engineRunning or 0) > 0.5
  local lights = (electrics.values.lights_state or 0) > 0
  state.battery = rules.battery(state.battery, dt, ign >= 1, running, lights)
  if not running and ign >= 3 and not rules.canStart(state.battery) then
    electrics.setIgnitionLevel(2)                                             -- the starter just clicks
    if not flatWarned then
      flatWarned = true
      guihooks.message('The battery is flat. Jump it, or put a new one in (trunk, or the garage).', 6, 'slBattery')
    end
  elseif running then
    flatWarned = false
  end

  -- distance: wear and oil age, and the oil a worn engine loses
  local pos = obj:getPosition()
  if lastPos then
    local km = (pos - lastPos):length() / 1000
    if km < 0.2 then                                                          -- not a teleport
      state.engineKm = (state.engineKm or 0) + km
      state.oilKm = (state.oilKm or 0) + km
      local leak = rules.leakLitresPerKm(state.engineKm) * km
      if leak > 0 and oil then
        local capacity = math.max(1, (oil.initialMass or 4) / 0.88)
        setLevel(oil, (level(oil) or 1) - leak / capacity)
        leakCarry = leakCarry + leak
        if leakCarry > 0.02 then leakCarry = 0 drip('oil') end
      end
    end
  end
  lastPos = pos

  -- how it is driven (#30): the rev limiter, overheating, hard stops from speed, launches, hard landings. Sampled every frame, counted in seconds/events.
  local speed = obj:getVelocity():length()
  local rpmRatio = engine and engine.maxRPM and engine.maxRPM > 0 and (electrics.values.rpm or 0) / engine.maxRPM or 0
  local add = rules.abuseSample({ dt = dt, rpmRatio = rpmRatio, coolantC = engine and engine.thermals and engine.thermals.coolantTemperature, prevSpeed = prevSpeed,
    speed = speed, brake = electrics.values.brake, throttle = electrics.values.throttle })
  local ab = state.abuse
  ab.engine, ab.brakes, ab.drive = (ab.engine or 0) + add.engine, (ab.brakes or 0) + add.brakes, (ab.drive or 0) + add.drive
  abuseTimer = abuseTimer + dt
  if abuseTimer > 0.5 then
    abuseTimer = 0
    prevSpeed = speed
    local dmg = beamstate and beamstate.damage
    if dmg and lastDamage and dmg - lastDamage > 150 and dmg - lastDamage < 2000 then ab.susp = (ab.susp or 0) + (dmg - lastDamage) / 150 end      -- (a crash is counted by the career)
    lastDamage = dmg
  end

  capTimer = capTimer + dt
  if capTimer > 1 then capTimer = 0 applyFactor() end
  reportTimer = reportTimer + dt
  if reportTimer > 2 then reportTimer = 0 M.report() end
end

-- the weather's grip (#45): the tyres' friction, scaled on the tread nodes (a wet road). Reapplied after a reset, which restores the jbeam's values.
-- a wheel in a puddle has less grip of its own (aquaplaning, vehicle extension slPuddles), on top of the road's.
local gripFactor = 1
local function applyGrip()
  for wid, wheel in pairs(wheels and wheels.wheels or {}) do
    if wheel.treadNodes and not wheel.isTireDeflated then
      local f = gripFactor * (slPuddles and slPuddles.wheelFactor and slPuddles.wheelFactor(wid) or 1)
      for _, cid in pairs(wheel.treadNodes) do
        local n = v.data.nodes[cid]
        local fc = n and n.frictionCoef
        if fc then obj:setNodeFrictionSlidingCoefs(cid, fc * f, (n.slidingFrictionCoef or fc) * f) end
      end
    end
  end
end

function M.reapplyGrip() applyGrip() end      -- (slPuddles changed a wheel's factor)

function M.setGrip(f)
  f = math.max(0.3, math.min(1.2, tonumber(f) or 1))
  if math.abs(f - gripFactor) < 1e-3 then return end
  gripFactor = f
  applyGrip()
end

function M.onReset()
  if gripFactor ~= 1 then applyGrip() end
  findFluids()
  lastPos = nil
  applyFactor()
end

M.onExtensionLoaded = function() findFluids() end

return M
