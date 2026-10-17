-- Finds the part change that crashes a car when a lot rebuilds it (T29). Runs in the game's GE Lua (run_lua), with a level loaded:
--   node bng.js run_lua @tools/probe_tweak.lua
-- Settings (set as globals BEFORE running it, with run_lua "PROBE_MODEL='midtruck' PROBE_GUARDED=true"):
--   PROBE_MODEL    the model, default 'midtruck'
--   PROBE_GUARDED  true: with the slot guards of carsLib.tweakTree (core slots kept, only slot-legal swaps); default false (the old rules)
--   PROBE_ONLY     a label to run alone, e.g. 'fault battery' or 'swap seed 3'; default every change
--   PROBE_CONFIG   a config file name (part of it) to run alone; default every config of the model
--   PROBE_DENTS    true: instead of the part changes, do what a USED lot does to its cars: spawn every config, dent it (applyDents with
--                  keepLatches, damage 0.5), park-brake + freeze, leave it 2 s, delete it, for PROBE_ROUNDS (default 3) rounds
--   PROBE_EACH     with PROBE_DENTS: one dent per car instead of all of the lot's, damage 1: 'BEFORE dent <part path>' names the panel
-- For every stock config of the model: spawn it stock 20 m ahead of the player, then ONE change at a time (each fault's parts taken
-- off, then single swaps with seeds 1..8) rebuilt in place exactly as carBuilder.buildOffer does, left 3 s, back to stock.
-- EVERY step is written BEFORE it is done, to three places: the game's log (beamng.log, lines "probe_tweak"), the file
-- <user folder>/settings/street_legal/probe_tweak.txt (rewritten whole each step, flushed), and the global PROBE_LOG (a list of lines).
-- After a crash the last "BEFORE" line without its "OK" is the change.

local buffer = {}
local VFILE = '/settings/street_legal/probe_tweak.txt'
local function note(text)
  local line = os.date('%H:%M:%S ') .. text
  buffer[#buffer + 1] = line
  rawset(_G, 'PROBE_LOG', buffer)
  pcall(log, 'I', 'probe_tweak', line)
  pcall(writeFile, VFILE, table.concat(buffer, '\n') .. '\n')
end
note('probe_tweak starts; file ' .. VFILE .. ' (the game\'s virtual path: <user folder>/settings/street_legal/probe_tweak.txt)')

local okReq, builder = pcall(require, 'sl/carBuilder')
local okReq2, cars = pcall(require, 'sl/core/cars')
local okReq3, rngLib = pcall(require, 'sl/core/rng')
if not (okReq and okReq2 and okReq3) then
  note('ERROR: could not load the career modules: ' .. tostring(builder) .. ' ' .. tostring(cars) .. ' ' .. tostring(rngLib))
  return 'probe_tweak: modules missing, see PROBE_LOG'
end

local MODEL = rawget(_G, 'PROBE_MODEL') or 'midtruck'
local GUARDED = rawget(_G, 'PROBE_GUARDED') == true
local ONLY = rawget(_G, 'PROBE_ONLY')
local DENTS = rawget(_G, 'PROBE_DENTS') == true
local EACH = rawget(_G, 'PROBE_EACH') == true
local ROUNDS = tonumber(rawget(_G, 'PROBE_ROUNDS')) or 3
local CONFIG = rawget(_G, 'PROBE_CONFIG')
local FAULTS = { 'engine', 'gearbox', 'radiator', 'battery', 'tyres', 'brakes', 'exhaust' }

local function vehData(id) return id and core_vehicle_manager.getVehicleData(id) or nil end

-- (carBuilder's own rebuild in place, with its real-time end: false when the game did not report it within 8 s)
local function respawn(job, veh, cfg)
  local id = veh:getID()
  local before = vehData(id)
  veh:setDynDataFieldbyName('autoEnterVehicle', 0, 'false')
  veh:respawn(serialize(cfg))
  local started, ok = os.clock(), false
  repeat
    job.sleep(0.1)
    ok = vehData(id) ~= nil and vehData(id) ~= before
  until ok or os.clock() - started > 8
  job.sleep(0.4)
  return ok
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
for _, c in ipairs(builder.configs()) do
  if c.model == MODEL and (not CONFIG or tostring(c.config):find(CONFIG, 1, true)) then list[#list + 1] = c end
end
local total = #(builder.configs())
note(string.format('%d stock configs of %s (of %d the career knows), guarded=%s, only=%s, config=%s', #list, MODEL, total, tostring(GUARDED), tostring(ONLY), tostring(CONFIG)))
if #list == 0 then
  local models = {}
  for _, c in ipairs(builder.configs()) do models[c.model] = true end
  local names = {}
  for m in pairs(models) do names[#names + 1] = m end
  table.sort(names)
  note('no config of ' .. MODEL .. '; models the career knows: ' .. table.concat(names, ' '))
  return 'probe_tweak: no config of ' .. MODEL .. ', see PROBE_LOG'
end
rawset(_G, 'PROBE_STATUS', 'running')

local function body(job)
  local okp, paused = pcall(function() return simTimeAuthority and simTimeAuthority.getPause and simTimeAuthority.getPause() end)
  note('game paused: ' .. tostring(okp and paused) .. ' (job.sleep runs on game time: a paused or unfocused game makes the probe look stuck)')
  local pv = getPlayerVehicle(0)
  note('player vehicle: ' .. tostring(pv and pv:getJBeamFilename()))
  local pos = (pv and (pv:getPosition() + vec3(pv:getDirectionVector()) * 20) or vec3(0, 0, 0)) + vec3(0, 0, 0.5)
  if DENTS then
    for round = 1, ROUNDS do
      for _, c in ipairs(list) do
        note(string.format('round %d config %s', round, tostring(c.config)))
        note('BEFORE spawn ' .. tostring(c.config))
        local veh = builder.spawn(job, c.model, c.config, pos, quatFromDir(vec3(0, 1, 0), vec3(0, 0, 1)))
        note((veh and 'OK' or 'FAILED') .. ' spawn')
        if veh then
          local id = veh:getID()
          local vd = vehData(id)
          local rng = rngLib.new(round * 1000 + 7)
          local dents = cars.dents(vd and vd.config.partsTree, builder.classify(), rng, EACH and 1 or 0.5, {})      -- (no refusals: to find the panel)
          local lists = { dents }
          if EACH then
            lists = {}
            for _, d in ipairs(dents) do lists[#lists + 1] = { d } end
          end
          for k, list in ipairs(lists) do
            local names = {}
            for i, d in ipairs(list) do names[i] = tostring(d.partPath) .. ':' .. string.format('%.3f', d.dent or 0) end
            if EACH and k > 1 then
              veh = builder.spawn(job, c.model, c.config, pos, quatFromDir(vec3(0, 1, 0), vec3(0, 0, 1)))
              note((veh and 'OK' or 'FAILED') .. ' spawn (next panel)')
              if not veh then break end
              id = veh:getID()
            end
            note('BEFORE dent ' .. table.concat(names, ' '))
            builder.applyDents(veh, list, { keepLatches = true })
            veh:queueLuaCommand('input.event("parkingbrake", 1, FILTER_DIRECT) controller.setFreeze(1)')
            if EACH then
              job.sleep(2)
              note('OK dent')
              note('BEFORE delete')
              local v3 = getObjectByID(id)
              if v3 then v3:delete() end
              job.sleep(1)
              note('OK delete')
              veh = nil
            end
          end
          if not veh then goto continue end
          job.sleep(2)
          note('OK dents')
          note('BEFORE delete')
          local v2 = getObjectByID(id)
          if v2 then v2:delete() end
          job.sleep(1)
          note('OK delete')
        end
        ::continue::
      end
    end
    note('== DONE (dents) ==')
    rawset(_G, 'PROBE_STATUS', 'done')
    return
  end
  for _, c in ipairs(list) do
    note('config ' .. tostring(c.config))
    note('BEFORE spawn ' .. tostring(c.config))
    local veh = builder.spawn(job, c.model, c.config, pos, quatFromDir(vec3(0, 1, 0), vec3(0, 0, 1)))
    note((veh and 'OK' or 'FAILED') .. ' spawn')
    if veh then
      local id = veh:getID()
      local base = deepcopy(vehData(id).config)
      local changes = {}
      for _, f in ipairs(FAULTS) do changes[#changes + 1] = { label = 'fault ' .. f, opts = { faults = { f }, mods = 0 } } end
      for seed = 1, 8 do changes[#changes + 1] = { label = 'swap seed ' .. seed, opts = { faults = {}, mods = 1, seed = seed } } end
      for _, ch in ipairs(changes) do
        if not ONLY or ONLY == ch.label then
          local cfg = deepcopy(base)
          local slotOf, partSlotType = lookups(id)
          local tw = cars.tweakTree(cfg.partsTree, { rng = rngLib.new(ch.opts.seed or 1), classify = builder.classify(), valueOf = function() return 0 end,
            faults = ch.opts.faults, mods = ch.opts.mods, slotOf = slotOf, partSlotType = partSlotType })
          if #tw.removed + #tw.swapped > 0 then
            local what = {}
            for _, p in ipairs(tw.removed) do what[#what + 1] = '-' .. p end
            for _, x in ipairs(tw.swapped) do what[#what + 1] = tostring(x.path) .. ' ' .. tostring(x.from) .. '>' .. tostring(x.to) end
            note('BEFORE ' .. ch.label .. ': ' .. table.concat(what, ' | '))
            local done = respawn(job, veh, cfg)
            if not done then note('TIMEOUT ' .. ch.label .. ': the game did not report the rebuild in 8 s; this car is dropped') break end
            job.sleep(3)
            veh = getObjectByID(id)
            note('OK ' .. ch.label .. (veh and '' or ' (vehicle gone)'))
            if not veh then break end
            note('BEFORE back to stock')
            done = respawn(job, veh, deepcopy(base))
            if not done then note('TIMEOUT back to stock: this car is dropped') break end
            job.sleep(1)
            veh = getObjectByID(id)
            note('OK back to stock')
            if not veh then break end
          else
            note('skip ' .. ch.label .. ' (the tweak changes nothing on this car)')
          end
        end
      end
      if veh then veh:delete() end
    end
  end
  note('== DONE ==')
  rawset(_G, 'PROBE_STATUS', 'done')
end

core_jobsystem.create(function(job)
  local ok, err = xpcall(function() body(job) end, debug.traceback)
  if not ok then
    note('ERROR in the probe: ' .. tostring(err))
    rawset(_G, 'PROBE_STATUS', 'error')
  end
end)
return 'probe_tweak started; progress in the game log (grep probe_tweak), ' .. VFILE .. ' and PROBE_LOG'
