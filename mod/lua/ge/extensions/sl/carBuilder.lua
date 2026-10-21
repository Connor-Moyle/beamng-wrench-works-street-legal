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

-- Spawn cost (A12): the first spawn of a model parses every jbeam file of its folder (the game's jbeam/io keeps them in a cache after that), which is a large
-- part of the freeze inside spawnNewVehicle. preloadModel fills that cache for a model ahead of time (without making a car), at a moment of our choosing.
-- Returns the milliseconds it took, and whether the model was in the cache already (nothing to parse).
local seenModels = {}
function M.preloadModel(model)
  if type(model) ~= 'string' or model == '' or seenModels[model] or (M.preloaded and M.preloaded[model]) then return 0, true end
  local ok, io = pcall(require, 'jbeam/io')
  if not ok or not io or not io.startLoading then return 0, false end
  local t0 = os.clock()
  local done = pcall(io.startLoading, { '/vehicles/' .. model .. '/', '/vehicles/common/' })
  local stats = io.getLastStartLoadingStats and io.getLastStartLoadingStats() or {}
  if io.finishLoading then pcall(io.finishLoading) end
  local ms = (os.clock() - t0) * 1000
  log('I', 'street_legal', string.format('preload %s: %.0f ms (jbeam files %s, already cached %s)', model, ms, tostring(stats.total), tostring(stats.cachedHits)))
  M.preloaded = M.preloaded or {}
  M.preloaded[model] = ms
  return ms, (stats.cachedHits or 0) >= (stats.total or 1) and (stats.total or 0) > 0
end

-- a vehicle spawned, not driven by the player. config: a .pc path or a config table. nobodyDrives: a lot's display car
-- or one of the player's own (the player's driver is a full one): Drivers & Pedestrians gives it no driver props
-- playerCar: a car the player owns: Drivers & Pedestrians gives it the rigged (flex) driver; everything else (traffic, stock, rivals) keeps props
function M.spawn(job, model, config, pos, rot, nobodyDrives, playerCar)
  if playerCar and slrrDriverMount and slrrDriverMount.playerCarNext then slrrDriverMount.playerCarNext() end
  if nobodyDrives and slrrDriverMount and slrrDriverMount.noPropsNext then slrrDriverMount.noPropsNext() end
  local t0 = os.clock()
  local firstOfModel = not seenModels[model]
  seenModels[model] = true
  local ok, veh = pcall(core_vehicles.spawnNewVehicle, model, {
    config = config, pos = pos, rot = rot, autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false,
  })
  local callMs = (os.clock() - t0) * 1000
  if nobodyDrives and slrrDriverMount and slrrDriverMount.noPropsDone then slrrDriverMount.noPropsDone() end   -- (the hook has run inside the call)
  if playerCar and slrrDriverMount and slrrDriverMount.playerCarDone then slrrDriverMount.playerCarDone() end
  if not ok or not veh then
    -- why: pcall's error text if it threw, else the game answered nothing (nil); the setup it was given, so a bad one can be told from a bad model
    local what = type(config) == 'string' and ('config file ' .. config .. (FS:fileExists(config) and ' (exists)' or ' (MISSING)'))
      or type(config) == 'table' and string.format('config table: model %s, main part %s, %d top slots, vars %s, paints %s', tostring(config.model),
        tostring(config.partsTree and config.partsTree.chosenPartName), (function() local n = 0 for _ in pairs(config.partsTree and config.partsTree.children or {}) do n = n + 1 end return n end)(),
        tostring(config.vars ~= nil), tostring(config.paints ~= nil))
      or tostring(config)
    log('W', 'street_legal', 'could not spawn ' .. tostring(model) .. ': ' .. (ok and 'the game answered nil' or ('error: ' .. tostring(veh))) .. '; ' .. what
      .. '; model known to the game: ' .. tostring(core_vehicles.getModel and core_vehicles.getModel(model) ~= nil))
    return nil
  end
  local id = veh:getID()
  if not waitData(job, id) then log('W', 'street_legal', 'spawn ' .. tostring(model) .. ': the game never reported the car built (15 s): left out') return nil end
  job.sleep(0.2)
  -- A12: what a spawn costs. callMs is the game standing still inside spawnNewVehicle (the lag the player feels); the rest is waiting between frames
  M.lastSpawn = { model = model, callMs = callMs, totalMs = (os.clock() - t0) * 1000 }
  M.lastSpawn.first = firstOfModel
  local stats = require('jbeam/io').getLastStartLoadingStats and require('jbeam/io').getLastStartLoadingStats() or {}
  log('I', 'street_legal', string.format('spawn %s: %.0f ms inside the game call, %.0f ms until built (%s; jbeam files %s, from the cache %s)', tostring(model), callMs, M.lastSpawn.totalMs,
    firstOfModel and 'first of its model this session' or 'model seen before', tostring(stats.total), tostring(stats.cachedHits)))
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
  local vd = type(id) == 'table' and id or vehData(id)       -- (a table: { ioCtx, config } read without a car, offlineData)
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
  local vd = type(id) == 'table' and id or vehData(id)
  local ok, jbeamIO = pcall(require, 'jbeam/io')
  return function(name)
    if not vd or not ok then return name end
    local okPart, part = pcall(jbeamIO.getPart, vd.ioCtx, name)
    local n = okPart and part and part.information and part.information.name
    return (type(n) == 'string' and n ~= '' and not n:find('{{', 1, true)) and n or name      -- (an unfilled template is no name)
  end
end

-- A stock car made into a custom one. recipe = { stage = 0..3 | 'race', seed }: the parts the
-- stage calls for, at their best, and the paint job that goes with the seed. Returns the vehicle.
-- A custom car is spawned stock and then spawned AGAIN with its parts changed (two freezes of 1-1.4 s, 2 s apart: the pairs in the hitch recordings).
-- The finished setup is remembered per car recipe, so the next time the same car is built (a racer back from the pool, the same meet) it is one spawn.
M.CACHE_MAX = 24
local customCache, customOrder = {}, {}
M.OFFLINE_TREE = true      -- false: a first build is stock car + rebuild, as before

-- a model's parts tree for a config (a .pc path or a table), read from the jbeam files with NO car spawned (the game's loadJbeamOnlyConfig, as its tech API
-- uses it). -> { ioCtx, config } or nil (then the long way); call finishOffline(jbeamIO) when done
local function offlineData(model, config)
  local okIo, jbeamIO = pcall(require, 'jbeam/io')
  local okLd, loader = pcall(require, 'jbeam/loader')
  if not (okIo and okLd and loader.loadJbeamOnlyConfig and core_vehicle_partmgmt and core_vehicle_partmgmt.buildConfigFromString) then return nil end
  local ok, vd = pcall(function()
    local dir = '/vehicles/' .. model .. '/'
    local dirs = { dir, '/vehicles/common/' }
    local input, isConfig = config, true
    if type(config) == 'string' then input, isConfig = core_vehicle_partmgmt.buildConfigFromString(dir, config) end
    if not (isConfig and type(input) == 'table') then return nil end
    local cfg = loader.loadJbeamOnlyConfig(dirs, deepcopy(input))
    if not (cfg and type(cfg.partsTree) == 'table') then return nil end
    return { ioCtx = jbeamIO.startLoading(dirs), config = cfg }
  end)
  if ok and vd then return vd, jbeamIO end
  pcall(jbeamIO.finishLoading)                                  -- (a half-open loading state must not stay)
  return nil
end

-- the part chosen at a path in a parts tree (the live car's, to check what was asked for)
local function partAt(node, path)
  if type(node) ~= 'table' then return nil end
  if node.path == path then return node.chosenPartName end
  for _, child in pairs(node.children or {}) do
    local found = partAt(child, path)
    if found then return found end
  end
end

function M.buildCustom(job, model, config, recipe, pos, rot, nobodyDrives)
  local key = table.concat({ tostring(model), type(config) == 'table' and 'table' or tostring(config), tostring(recipe.stage), tostring(recipe.seed) }, '|')
  if customCache[key] then
    local v = M.spawn(job, model, deepcopy(customCache[key]), pos, rot, nobodyDrives)
    if v then return v end
    customCache[key] = nil                                      -- (it did not take: built the long way below)
  end
  -- the parts tree without a spawn: one spawn for a custom car, the first time too
  if M.OFFLINE_TREE and (not sl_options or sl_options.get('slOfflineTree') ~= false) then
    local t0 = os.clock()
    local od, jbeamIO = offlineData(model, config)
    if od then
      local cfg = deepcopy(od.config)
      local okApply, result = pcall(buildsLib.apply, cfg.partsTree, { stage = recipe.stage, rng = rngLib.new(recipe.seed or 1), classify = classify(),
        valueOf = valueOf(od), nameOf = nameOf(od) })
      if jbeamIO and jbeamIO.finishLoading then pcall(jbeamIO.finishLoading) end
      if okApply and result and #result.upgraded + #result.stripped > 0 then
        cfg.paints = buildsLib.paints(recipe.seed or 1, recipe.stage == 'race')
        local keep = deepcopy(cfg)
        local readMs = (os.clock() - t0) * 1000
        local v = M.spawn(job, model, cfg, pos, rot, nobodyDrives)
        if v then
          -- did the car come out with what was asked for: one changed slot against the live car's tree
          local up = result.upgraded[1]
          local vdLive = up and vehData(v:getID())
          local live = vdLive and vdLive.config and partAt(vdLive.config.partsTree, up.path)
          if up and live ~= up.to then
            log('W', 'street_legal', string.format('offline build mismatch: %s %s asked for %s, the car has %s; offline tree switched off', tostring(model), tostring(up.path), tostring(up.to), tostring(live)))
            M.OFFLINE_TREE = false
          else
            log('I', 'street_legal', string.format('offline tree: %s read in %.0f ms, %d parts changed, one spawn', tostring(model), readMs, #result.upgraded + #result.stripped))
          end
          if type(config) ~= 'table' and not customCache[key] then
            customCache[key] = keep
            customOrder[#customOrder + 1] = key
            if #customOrder > M.CACHE_MAX then customCache[table.remove(customOrder, 1)] = nil end
          end
          return v
        end
      end
    else
      log('W', 'street_legal', 'buildCustom ' .. tostring(model) .. ': the parts tree could not be read without a car; built the long way')
    end
  end
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
    job.sleep(1)                                                -- (the frames come back between the two spawns)
    local keep = deepcopy(cfg)
    veh = rebuild(job, veh, model, cfg, pos, rot, nobodyDrives)
    if not veh then return nil end
    if type(config) ~= 'table' and not customCache[key] then
      customCache[key] = keep
      customOrder[#customOrder + 1] = key
      if #customOrder > M.CACHE_MAX then customCache[table.remove(customOrder, 1)] = nil end
    end
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
-- a car made from an offer (a lot's, a delivery, a private sale), dressed with the dirt its condition and mileage give it (Car Surface FX, if it is there)
function M.buildOffer(job, offer, pos, rot, opts)
  local veh, extra = M.buildOfferPlain(job, offer, pos, rot, opts)
  if veh and sl_surfacefx and sl_surfacefx.dress then pcall(sl_surfacefx.dress, veh:getID(), offer) end
  return veh, extra
end

function M.buildOfferPlain(job, offer, pos, rot, opts)
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
M.APPLY_DAMAGE_ON_SPAWN = true
-- one of the player's cars, from its record
-- A car of the player's must never become unspawnable: its saved setup, then the whole setup from before parts were struck off, then the game's stock
-- default for the model, each tried only if the one before gave nothing (logged which one worked).
function M.spawnOwned(job, car, pos, rot)
  if type(car.config) ~= 'table' and not car.pcPath then return nil end          -- (a loaner has no saved setup, only the path of its config file)
  local function cfgOf(c) return { model = c.model or car.model, partsTree = c.partsTree, vars = c.vars, paints = c.paints } end
  local attempts = {}
  if car.pcPath then attempts[#attempts + 1] = { 'config file', car.pcPath } end
  if type(car.config) == 'table' then attempts[#attempts + 1] = { 'saved setup', cfgOf(car.config) } end
  if type(car.fullConfig) == 'table' then attempts[#attempts + 1] = { 'setup before parts were struck off', cfgOf(car.fullConfig) } end
  local m = core_vehicles.getModel and core_vehicles.getModel(car.model)
  local pc = m and m.model and m.model.default_pc
  if pc then attempts[#attempts + 1] = { 'stock default', 'vehicles/' .. car.model .. '/' .. pc .. '.pc' } end
  local veh
  for i, a in ipairs(attempts) do
    veh = M.spawn(job, car.model, a[2], pos, rot, not M.PLAYER_DRIVER_PROPS, true)
    if veh then
      if i > 1 then
        log('W', 'street_legal', 'owned car ' .. tostring(car.name) .. ': the ' .. attempts[1][1] .. ' would not spawn, built from the ' .. a[1])
        if i == 2 and not car.pcPath then car.config, car.fullConfig = car.fullConfig, nil end          -- (the whole setup is the car again)
      end
      break
    end
  end
  if not veh then return nil end
  job.sleep(0.3)
  -- the car's recorded damage goes on only when its own Lua says it has settled (slrrGarageVeh.apply waits for 30 frames and a second; a crash 0.3 s after a
  -- build, in the physics thread, 0x140386, came from putting it on at a fixed time). M.APPLY_DAMAGE_ON_SPAWN = false: the car comes out undamaged.
  if M.APPLY_DAMAGE_ON_SPAWN then M.applyDamage(veh, car.damage) end
  return veh
end

M.classify = classify
return M
