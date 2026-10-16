-- Street Legal Racing: putting cars into the world.
-- The stock cars the market and the racers draw from, building a car for sale the way its
-- offer says (sl/core/cars does the deciding), spawning the player's own cars from their
-- saved setup and dents, and reading a live car back into a saveable record.
-- Not an extension: required by the lot, the fleet and the street racing. Calls that wait
-- take a job (core_jobsystem) as their first argument.

local M = {}

local carsLib = require('sl/core/cars')
local buildsLib = require('sl/core/builds')
local rngLib = require('sl/core/rng')

local configCache

local function classify()
  local ok, catalog = pcall(require, 'slrr/garageCatalog')
  return ok and catalog.classify or function() return 'body', 'misc' end
end

-- the game's own stock cars: { model, config, name, brand, pw, power, weight, value }
function M.configs()
  if configCache then return configCache end
  configCache = {}
  local ok, list = pcall(function() return core_vehicles.getConfigList(true).configs end)
  for _, c in ipairs(ok and type(list) == 'table' and list or {}) do
    local power, weight, value = tonumber(c.Power), tonumber(c.Weight), tonumber(c.Value)
    if power and weight and value and power > 40 and weight > 500 and weight < 3500 and value > 0 and c.pcFilename
        and (c.Source == nil or c.Source == 'BeamNG - Official') then
      local model = core_vehicles.getModel(c.model_key)
      local info = model and model.model or {}
      if info.Type == 'Car' or info.Type == 'Truck' then
        configCache[#configCache + 1] = {
          model = c.model_key, config = c.pcFilename, name = tostring(c.Name or c.model_key), brand = tostring(info.Brand or ''),
          power = power, weight = weight, pw = power / weight, value = value, raw = c,       -- (raw: the game's entry, for a dealer's filter)
        }
      end
    end
  end
  return configCache
end

local function vehData(id) return id and core_vehicle_manager.getVehicleData(id) or nil end

local function waitData(job, id, seconds)
  local t = 0
  while t < (seconds or 15) do
    if vehData(id) then return true end
    job.sleep(0.1)
    t = t + 0.1
  end
  return false
end

-- a vehicle spawned, not driven by the player. config: a .pc path or a config table
function M.spawn(job, model, config, pos, rot)
  local ok, veh = pcall(core_vehicles.spawnNewVehicle, model, {
    config = config, pos = pos, rot = rot, autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false,
  })
  if not ok or not veh then
    log('W', 'street_legal', 'could not spawn ' .. tostring(model) .. ': ' .. tostring(veh))
    return nil
  end
  local id = veh:getID()
  if not waitData(job, id) then return nil end
  job.sleep(0.2)
  return getObjectByID(id)
end

-- rebuild a spawned car with another setup; waits until the game has done it
local function respawn(job, veh, config)
  local id = veh:getID()
  local before = vehData(id)
  -- a respawned car takes the player unless told not to (seen in game: every racer built for a
  -- meet or the streets became the player's car); the game's own replaceVehicle does the same
  veh:setDynDataFieldbyName('autoEnterVehicle', 0, 'false')
  veh:respawn(serialize(config))
  local t = 0
  repeat
    job.sleep(0.1)
    t = t + 0.1
  until (vehData(id) and vehData(id) ~= before) or t > 8
  job.sleep(0.4)
end

-- bend panels in the shape Wrench Works' vehicle extension knows (it keeps them through rebuilds)
function M.applyDents(veh, dents)
  if not veh or not dents or #dents == 0 then return end
  local beams = {}
  for _, d in ipairs(dents) do beams[#beams + 1] = { dent = d.dent, seed = d.seed, pa = d.partPath, pb = d.partPath } end
  veh:queueLuaCommand('extensions.load("slrrGarageVeh") if slrrGarageVeh then slrrGarageVeh.apply(' .. serialize({ nodes = {}, beams = beams }) .. ') end')
end

function M.applyDamage(veh, damage)
  if not veh or type(damage) ~= 'table' or #(damage.beams or {}) == 0 then return end
  veh:queueLuaCommand('extensions.load("slrrGarageVeh") if slrrGarageVeh then slrrGarageVeh.apply(' .. serialize(damage) .. ') end')
end

-- what a part is worth, from its jbeam
local function valueOf(id)
  local vd = vehData(id)
  local ok, jbeamIO = pcall(require, 'jbeam/io')
  return function(name)
    if not vd or not ok then return 0 end
    local okPart, part = pcall(jbeamIO.getPart, vd.ioCtx, name)
    return okPart and part and part.information and tonumber(part.information.value) or 0
  end
end

-- what every part on a live car is worth together (its jbeam values; nil when the car isn't built)
function M.partsValue(id)
  local vd = vehData(id)
  local tree = vd and vd.config and vd.config.partsTree
  if not tree then return nil end
  local value, total = valueOf(id), 0
  local function walk(node)
    if type(node) ~= 'table' then return end
    if type(node.chosenPartName) == 'string' and node.chosenPartName ~= '' then total = total + value(node.chosenPartName) end
    for _, child in pairs(node.children or {}) do walk(child) end
  end
  walk(tree)
  return total
end

-- what a part is called, from its jbeam
local function nameOf(id)
  local vd = vehData(id)
  local ok, jbeamIO = pcall(require, 'jbeam/io')
  return function(name)
    if not vd or not ok then return name end
    local okPart, part = pcall(jbeamIO.getPart, vd.ioCtx, name)
    return okPart and part and part.information and tostring(part.information.name or name) or name
  end
end

-- A stock car made into a custom one. recipe = { stage = 0..3 | 'race', seed }: the parts the
-- stage calls for, at their best, and the paint job that goes with the seed. Returns the vehicle.
function M.buildCustom(job, model, config, recipe, pos, rot)
  local veh = M.spawn(job, model, config, pos, rot)
  if not veh then return nil end
  local id = veh:getID()
  local vd = vehData(id)
  local cfg = deepcopy(vd.config)
  local result = buildsLib.apply(cfg.partsTree, { stage = recipe.stage, rng = rngLib.new(recipe.seed or 1), classify = classify(),
    valueOf = valueOf(id), nameOf = nameOf(id) })
  local paints = buildsLib.paints(recipe.seed or 1, recipe.stage == 'race')
  if #result.upgraded + #result.stripped > 0 then
    cfg.paints = paints
    respawn(job, veh, cfg)
    veh = getObjectByID(id)
  else
    -- nothing to change underneath: just the paint, without a rebuild
    for i, p in ipairs(paints) do pcall(core_vehicle_manager.liveUpdateVehicleColors, id, veh, i, p) end
  end
  return veh
end

-- A car for sale, built as its offer describes: stock, then parts swapped and taken off, then dented.
-- A track special is built as a race car instead. Returns the vehicle (nil if it could not be made).
function M.buildOffer(job, offer, pos, rot)
  if offer.build then
    local veh = M.buildCustom(job, offer.model, offer.config, { stage = offer.build, seed = rngLib.hash(offer.id) }, pos, rot)
    if veh then veh:queueLuaCommand('input.event("parkingbrake", 1, FILTER_DIRECT) controller.setFreeze(1)') end
    return veh, { removed = {}, swapped = {} }
  end
  local veh = M.spawn(job, offer.model, offer.config, pos, rot)
  if not veh then return nil end
  local id = veh:getID()
  local vd = vehData(id)
  local rng = rngLib.new(rngLib.hash(offer.id))
  local cfg = deepcopy(vd.config)
  local tweak = carsLib.tweakTree(cfg.partsTree, { rng = rng, classify = classify(), valueOf = valueOf(id), faults = offer.faults, mods = offer.mods })
  if #tweak.removed + #tweak.swapped > 0 then
    respawn(job, veh, cfg)
    veh = getObjectByID(id)
    if not veh then return nil end
  end
  vd = vehData(id)
  local dents = carsLib.dents(vd and vd.config.partsTree or cfg.partsTree, classify(), rng, offer.damage)
  M.applyDents(veh, dents)
  -- a car on a lot does not roll away
  veh:queueLuaCommand('input.event("parkingbrake", 1, FILTER_DIRECT) controller.setFreeze(1)')
  return veh, tweak
end

-- the setup of a live car, as saved: { model, partsTree, vars, paints }
function M.configOf(id)
  local veh, vd = getObjectByID(id), vehData(id)
  if not veh or not vd then return nil end
  return { model = veh:getJBeamFilename(), partsTree = deepcopy(vd.config.partsTree), vars = deepcopy(vd.config.vars), paints = deepcopy(vd.config.paints) }
end

-- one of the player's cars, from its record
function M.spawnOwned(job, car, pos, rot)
  if type(car.config) ~= 'table' then return nil end
  local cfg = { model = car.config.model or car.model, partsTree = car.config.partsTree, vars = car.config.vars, paints = car.config.paints }
  local veh = M.spawn(job, car.model, cfg, pos, rot)
  if not veh then return nil end
  job.sleep(0.3)
  M.applyDamage(veh, car.damage)
  return veh
end

M.classify = classify
return M
