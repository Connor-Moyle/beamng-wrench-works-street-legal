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

-- Models no lot, dealer or private seller lists (the manager's decision for release 1): the midtruck crashed the game natively and
-- intermittently, at the same place, on its first spawn too, whatever was done to it (T29). Add a model here from the console if
-- another does the same: require('sl/carBuilder').LOT_EXCLUDE_MODELS.somecar = true.
M.LOT_EXCLUDE_MODELS = { midtruck = true }

-- the special-order cars (sl/core/cars SPECIAL_ORDER: the Wydra and the other odd models), for the factory's "Special order" group: every drivable
-- config of those models, in the same shape as configs() but without its power and weight limits (a quad bike is light). Props, trailers and the
-- unicycle are special-order for the pools (nobody sees them) but nothing to order, so not here.
local NOT_ORDERABLE = { unicycle = true, simple_traffic = true }
local specialCache
function M.specialOrder()
  if specialCache then return specialCache end
  specialCache = {}
  local ok, list = pcall(function() return core_vehicles.getConfigList(true).configs end)
  for _, c in ipairs(ok and type(list) == 'table' and list or {}) do
    local value = tonumber(c.Value)
    if value and value > 0 and c.pcFilename and (c.Source == nil or c.Source == 'BeamNG - Official') and not NOT_ORDERABLE[c.model_key] then
      local model = core_vehicles.getModel(c.model_key)
      local info = model and model.model or {}
      local entry = { model = c.model_key, config = c.pcFilename, name = tostring(c.Name or c.model_key), brand = tostring(info.Brand or ''),
        power = tonumber(c.Power) or 0, weight = tonumber(c.Weight) or 0, value = value, raw = c }
      local drivable = info.Type == 'Car' or info.Type == 'Truck' or info.Type == 'Heavy Machinery'
      if drivable and carsLib.isSpecialOrder(entry) then
        entry.pw = entry.weight > 0 and entry.power / entry.weight or 0
        specialCache[#specialCache + 1] = entry
      end
    end
  end
  return specialCache
end

-- the cars the career builds for its AI (street racers and their opponents): every config except the excluded models (a racer may drive a
-- race car or a police car; no lot sells those)
function M.aiPool()
  local out = {}
  for _, c in ipairs(carsLib.withoutModels(M.configs(), M.LOT_EXCLUDE_MODELS)) do
    if carsLib.racerOk(c) then out[#out + 1] = c end          -- (no limousine, bus, van, truck, ambulance or police car races)
  end
  return out
end

-- the cars a lot or a private seller may offer: not the police, service or race cars, not an excluded model (sl/core/stockdealers.lotPool)
function M.forSale()
  return require('sl/core/stockdealers').lotPool(M.configs(), M.LOT_EXCLUDE_MODELS)
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

-- a vehicle spawned, not driven by the player. config: a .pc path or a config table. nobodyDrives: a lot's display car
-- or one of the player's own (the player's driver is a full one): Drivers & Pedestrians gives it no driver props
function M.spawn(job, model, config, pos, rot, nobodyDrives)
  if nobodyDrives and slrrDriverMount and slrrDriverMount.noPropsNext then slrrDriverMount.noPropsNext() end
  local t0 = os.clock()
  local ok, veh = pcall(core_vehicles.spawnNewVehicle, model, {
    config = config, pos = pos, rot = rot, autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false,
  })
  local callMs = (os.clock() - t0) * 1000
  if nobodyDrives and slrrDriverMount and slrrDriverMount.noPropsDone then slrrDriverMount.noPropsDone() end   -- (the hook has run inside the call)
  if not ok or not veh then
    log('W', 'street_legal', 'could not spawn ' .. tostring(model) .. ': ' .. tostring(veh))
    return nil
  end
  local id = veh:getID()
  if not waitData(job, id) then log('W', 'street_legal', 'spawn ' .. tostring(model) .. ': the game never reported the car built (15 s): left out') return nil end
  job.sleep(0.2)
  -- A12: what a spawn costs. callMs is the game standing still inside spawnNewVehicle (the lag the player feels); the rest is waiting between frames
  M.lastSpawn = { model = model, callMs = callMs, totalMs = (os.clock() - t0) * 1000 }
  log('I', 'street_legal', string.format('spawn %s: %.0f ms inside the game call, %.0f ms until built', tostring(model), callMs, M.lastSpawn.totalMs))
  return getObjectByID(id)
end

-- Rebuild a spawned car with another setup: the stock car is deleted and a NEW one spawned with the final config at the same spot. Never
-- veh:respawn in place: three lot cars (midtruck twice, a pickup) corrupted the game's heap (0xC0000374) when rebuilt in place with a
-- tweaked parts tree. Returns the new vehicle, or nil when it could not be made (logged by spawn).
local function rebuild(job, veh, model, cfg, pos, rot, nobodyDrives)
  veh:delete()
  job.sleep(0.5)
  return M.spawn(job, model, cfg, pos, rot, nobodyDrives)
end

-- bend panels in the shape Wrench Works' vehicle extension knows (it keeps them through rebuilds)
-- options.keepLatches: a car on show is bent without its latches being released (slrrGarageVeh would let them go and push
-- them shut again later: a held car's pushes hung the game while the next lot car was built beside it, T27)
function M.applyDents(veh, dents, options)
  if not veh or not dents or #dents == 0 then return end
  local beams = {}
  for _, d in ipairs(dents) do beams[#beams + 1] = { dent = d.dent, seed = d.seed, pa = d.partPath, pb = d.partPath } end
  veh:queueLuaCommand('extensions.load("slrrGarageVeh") if slrrGarageVeh then slrrGarageVeh.apply(' .. serialize({ nodes = {}, beams = beams }) .. ', ' .. serialize(options or {}) .. ') end')
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
function M.buildCustom(job, model, config, recipe, pos, rot, nobodyDrives)
  local veh = M.spawn(job, model, config, pos, rot, nobodyDrives)
  if not veh then return nil end
  local id = veh:getID()
  local vd = vehData(id)
  local cfg = deepcopy(vd.config)
  local result = buildsLib.apply(cfg.partsTree, { stage = recipe.stage, rng = rngLib.new(recipe.seed or 1), classify = classify(),
    valueOf = valueOf(id), nameOf = nameOf(id) })
  local paints = buildsLib.paints(recipe.seed or 1, recipe.stage == 'race')
  if #result.upgraded + #result.stripped > 0 then
    cfg.paints = paints
    veh = rebuild(job, veh, model, cfg, pos, rot, nobodyDrives)
    if not veh then return nil end
  else
    -- nothing to change underneath: just the paint, without a rebuild
    for i, p in ipairs(paints) do pcall(core_vehicle_manager.liveUpdateVehicleColors, id, veh, i, p) end
  end
  return veh
end

-- the game's slot rules for a car's parts tree: slotOf(node, parentNode) -> the slot's definition (from the parent part's
-- slots), partSlotType(partName) -> what the part is. nil, nil when the game's jbeam data is not reachable.
local function slotLookups(id)
  local vd = vehData(id)
  local ok, jbeamIO = pcall(require, 'jbeam/io')
  if not (vd and ok and vd.ioCtx) then return nil, nil end
  local cache = {}
  local function part(name)
    if type(name) ~= 'string' or name == '' then return nil end
    if cache[name] == nil then
      local okp, p = pcall(jbeamIO.getPart, vd.ioCtx, name)
      cache[name] = okp and type(p) == 'table' and p or false
    end
    return cache[name] or nil
  end
  local function slotOf(node, parent)
    local pp = parent and part(parent.chosenPartName)
    for _, sl in ipairs(pp and (pp.slots2 or pp.slots) or {}) do
      if (sl.name or sl.type) == node.id then return sl end
    end
  end
  return slotOf, function(name) local p = part(name) return p and p.slotType end
end

-- Models whose parts are not swapped or taken off for a lot (they stand stock, dented). Empty: the midtruck crashes (T29) came from a
-- swapped spare wheel, which M.REFUSE keeps from being changed on any model. Add a model here, or a word to M.REFUSE, if a car
-- ever crashes the game again.
M.NO_TWEAK_MODELS = {}
M.REFUSE_DENTS = {}             -- see carsLib.REFUSE_DENTS: panels a car is never dented on
M.NO_REBUILD = false           -- true: a lot car is spawned stock and never rebuilt (no part removed or swapped): bisecting the 0x140386 crash
M.NO_DENTS = false              -- true: a car for sale is not dented (bisect switch)
M.REFUSE = { 'sparewheel', 'spare_wheel', 'spare' }       -- (pieces of a slot path, slot id or part name that are never taken off or swapped)

-- Dents on one car, and a wait for the car itself to say they are on (a callback from its own Lua, slrrGarageVeh's options.done), then a
-- second for the engine to settle; then the car is frozen. Meant to run with nothing else spawning or rebuilding. Real-time end:
-- M.DENTS_WAIT seconds, logged. offer is only for the log.
M.DENTS_WAIT = 5
local dentsDone = {}
function M.onDentsDone(vid) dentsDone[vid] = true end
function M.dentCar(job, veh, dents, offer)
  if M.NO_DENTS or not veh or not dents or #dents == 0 then return true end
  local id = veh:getID()
  local t = {}
  for i, d in ipairs(dents) do t[i] = string.format('%s:%.3f', tostring(d.partPath), d.dent or 0) end
  log('I', 'street_legal', string.format('lot car %s: dents [%s]', tostring(offer and (offer.id .. ' ' .. tostring(offer.model)) or id), table.concat(t, ' ')))
  dentsDone[id] = nil
  M.applyDents(veh, dents, { keepLatches = true, done = string.format("require('sl/carBuilder').onDentsDone(%d)", id) })
  local started = os.clock()
  while not dentsDone[id] and os.clock() - started < M.DENTS_WAIT do job.sleep(0.1) end
  local ok = dentsDone[id] == true
  dentsDone[id] = nil
  if not ok then log('W', 'street_legal', 'TIMEOUT: vehicle ' .. tostring(id) .. ' did not report its dents in ' .. M.DENTS_WAIT .. ' s') end
  job.sleep(1)
  local v = getObjectByID(id)
  if v then v:queueLuaCommand('input.event("parkingbrake", 1, FILTER_DIRECT) controller.setFreeze(1)') end
  return ok
end

-- A car for sale, built as its offer describes: stock, then parts swapped and taken off, then dented.
-- A track special is built as a race car instead. Returns the vehicle (nil if it could not be made).
function M.buildOffer(job, offer, pos, rot, opts)
  if offer.build then
    local veh = M.buildCustom(job, offer.model, offer.config, { stage = offer.build, seed = rngLib.hash(offer.id) }, pos, rot, true)
    if veh then veh:queueLuaCommand('input.event("parkingbrake", 1, FILTER_DIRECT) controller.setFreeze(1)') end
    return veh, { removed = {}, swapped = {} }
  end
  local veh = M.spawn(job, offer.model, offer.config, pos, rot, true)
  if not veh then return nil end
  local id = veh:getID()
  local vd = vehData(id)
  local rng = rngLib.new(rngLib.hash(offer.id))
  local cfg = deepcopy(vd.config)
  local tweak
  if M.NO_TWEAK_MODELS[offer.model] then
    tweak = { removed = {}, swapped = {}, refused = {} }
  else
    local slotOf, partSlotType = slotLookups(id)
    tweak = carsLib.tweakTree(cfg.partsTree, { rng = rng, classify = classify(), valueOf = valueOf(id), faults = offer.faults, mods = offer.mods,
      slotOf = slotOf, partSlotType = partSlotType, refuse = M.REFUSE })
  end
  if #tweak.removed + #tweak.swapped + #(tweak.refused or {}) > 0 then       -- (one line a car: the last one before a crash names the change)
    local function paths(list, f) local t = {} for i, x in ipairs(list or {}) do t[i] = f(x) end return table.concat(t, ' ') end
    log('I', 'street_legal', string.format('lot car %s (%s, %s): removed [%s] swapped [%s] refused [%s]', tostring(offer.id), tostring(offer.model), tostring(offer.config),
      paths(tweak.removed, tostring), paths(tweak.swapped, function(x) return tostring(x.path) .. '=' .. tostring(x.from) .. '>' .. tostring(x.to) end),
      paths(tweak.refused, function(x) return tostring(x.path) .. ':' .. tostring(x.why) end)))
  end
  if #tweak.removed + #tweak.swapped > 0 and not M.NO_REBUILD then
    veh = rebuild(job, veh, offer.model, cfg, pos, rot, true)
    if not veh then return nil end
    id = veh:getID()
  end
  vd = vehData(id)
  local dents = carsLib.dents(vd and vd.config.partsTree or cfg.partsTree, classify(), rng, offer.damage, M.REFUSE_DENTS)
  if M.NO_DENTS then dents = {} end
  if #dents > 0 and opts and opts.deferDents then
    -- The dents go on later, one car at a time with nothing spawning meanwhile (T43: dents applied while the next car spawned beside
    -- it killed the game, with the dents of the car just rebuilt and the next car's spawn at the same instant). Until then: brake on.
    veh:queueLuaCommand('input.event("parkingbrake", 1, FILTER_DIRECT)')
    return veh, tweak, dents
  end
  if #dents > 0 then M.dentCar(job, veh, dents, offer) end
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

-- A4: the player's own car gets its driver as vehicle props, like traffic (drawn by the car, so it moves with it: the full driver was a separate object placed
-- a frame late: lag, TAA smear, no car in the mirrors). false: the full driver again (spawned without props). Spawn-time only: a car bought at a lot is
-- spawned for the lot without props and gets them the next time it is spawned from its record.
M.PLAYER_DRIVER_PROPS = true
-- one of the player's cars, from its record
function M.spawnOwned(job, car, pos, rot)
  if type(car.config) ~= 'table' then return nil end
  local cfg = { model = car.config.model or car.model, partsTree = car.config.partsTree, vars = car.config.vars, paints = car.config.paints }
  local veh = M.spawn(job, car.model, cfg, pos, rot, not M.PLAYER_DRIVER_PROPS)
  if not veh then return nil end
  job.sleep(0.3)
  M.applyDamage(veh, car.damage)
  return veh
end

M.classify = classify
return M
