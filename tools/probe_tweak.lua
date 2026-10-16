-- Finds the part change that crashes a car when a lot rebuilds it (T29). Runs in the game's GE Lua (run_lua), with a level loaded:
--   PROBE_MODEL = 'midtruck'   (optional, default midtruck)      PROBE_GUARDED = true  (optional: with the slot guards, default off)
--   node bng.js run_lua @tools/probe_tweak.lua                    then, to read the log:  see PROBE_FILE below
-- For every stock config of the model: spawn it stock 20 m ahead of the player, then ONE change at a time (each fault's parts
-- taken off, then single swaps with seeds 1..8) rebuilt in place exactly as carBuilder.buildOffer does, left 3 s, back to stock.
-- Every step is written to the file BEFORE it is done and flushed: after a crash the last "BEFORE" without its "OK" is the change.

local builder = require('sl/carBuilder')
local cars = require('sl/core/cars')
local rngLib = require('sl/core/rng')

local MODEL = rawget(_G, 'PROBE_MODEL') or 'midtruck'
local GUARDED = rawget(_G, 'PROBE_GUARDED') == true
local FILE = (FS:getUserPath() or '') .. 'settings/street_legal/probe_tweak.txt'
local FAULTS = { 'engine', 'gearbox', 'radiator', 'battery', 'tyres', 'brakes', 'exhaust' }

pcall(function() FS:directoryCreate((FS:getUserPath() or '') .. 'settings/street_legal/', true) end)
local function note(text)
  local f = io.open(FILE, 'a')
  if f then f:write(os.date('%H:%M:%S ') .. text .. '\n') f:close() end
end

local function vehData(id) return id and core_vehicle_manager.getVehicleData(id) or nil end

-- (carBuilder's own rebuild in place)
local function respawn(job, veh, cfg)
  local id = veh:getID()
  local before = vehData(id)
  veh:setDynDataFieldbyName('autoEnterVehicle', 0, 'false')
  veh:respawn(serialize(cfg))
  local t = 0
  repeat job.sleep(0.1) t = t + 0.1 until (vehData(id) and vehData(id) ~= before) or t > 8
  job.sleep(0.4)
end

local function lookups(id)
  local vd = vehData(id)
  local ok, jbeamIO = pcall(require, 'jbeam/io')
  if not (GUARDED and vd and ok and vd.ioCtx) then return nil, nil end
  local cache = {}
  local function part(name)
    if type(name) ~= 'string' or name == '' then return nil end
    if cache[name] == nil then local okp, p = pcall(jbeamIO.getPart, vd.ioCtx, name) cache[name] = okp and type(p) == 'table' and p or false end
    return cache[name] or nil
  end
  return function(node, parent)
    local pp = parent and part(parent.chosenPartName)
    for _, sl in ipairs(pp and (pp.slots2 or pp.slots) or {}) do if (sl.name or sl.type) == node.id then return sl end end
  end, function(name) local p = part(name) return p and p.slotType end
end

local list = {}
for _, c in ipairs(builder.configs()) do if c.model == MODEL then list[#list + 1] = c end end
if #list == 0 then return 'no config of ' .. MODEL end
rawset(_G, 'PROBE_STATUS', 'running')
note(string.format('== probe %s, %d configs, guarded=%s ==', MODEL, #list, tostring(GUARDED)))

core_jobsystem.create(function(job)
  local pv = getPlayerVehicle(0)
  local pos = (pv and (pv:getPosition() + vec3(pv:getDirectionVector()) * 20) or vec3(0, 0, 0)) + vec3(0, 0, 0.5)
  for _, c in ipairs(list) do
    note('config ' .. tostring(c.config))
    local veh = builder.spawn(job, c.model, c.config, pos, quatFromDir(vec3(0, 1, 0), vec3(0, 0, 1)))
    if veh then
      local id = veh:getID()
      local base = deepcopy(vehData(id).config)
      local changes = {}
      for _, f in ipairs(FAULTS) do changes[#changes + 1] = { label = 'fault ' .. f, opts = { faults = { f }, mods = 0 } } end
      for seed = 1, 8 do changes[#changes + 1] = { label = 'swap seed ' .. seed, opts = { faults = {}, mods = 1, seed = seed } } end
      for _, ch in ipairs(changes) do
        local cfg = deepcopy(base)
        local slotOf, partSlotType = lookups(id)
        local tw = cars.tweakTree(cfg.partsTree, { rng = rngLib.new(ch.opts.seed or 1), classify = builder.classify(), valueOf = function() return 0 end,
          faults = ch.opts.faults, mods = ch.opts.mods, slotOf = slotOf, partSlotType = partSlotType })
        if #tw.removed + #tw.swapped > 0 then
          local what = {}
          for _, p in ipairs(tw.removed) do what[#what + 1] = '-' .. p end
          for _, x in ipairs(tw.swapped) do what[#what + 1] = tostring(x.path) .. ' ' .. tostring(x.from) .. '>' .. tostring(x.to) end
          note('BEFORE ' .. ch.label .. ': ' .. table.concat(what, ' | '))
          respawn(job, veh, cfg)
          job.sleep(3)
          veh = getObjectByID(id)
          note('OK ' .. ch.label .. (veh and '' or ' (vehicle gone)'))
          if not veh then break end
          note('BEFORE back to stock')
          respawn(job, veh, deepcopy(base))
          job.sleep(1)
          veh = getObjectByID(id)
          note('OK back to stock')
          if not veh then break end
        end
      end
      if veh then veh:delete() end
    end
  end
  note('== DONE ==')
  rawset(_G, 'PROBE_STATUS', 'done')
end)
return 'probe started; progress in ' .. FILE
