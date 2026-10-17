-- Wrench Works: Street Legal: the performance overlay (extension name: sl_perf; #49)
-- A small box top-left: frame time and fps, the worst frame of the last 10 s, video memory, and how many cars (traffic, others), pedestrians and
-- static objects are in the world, so a stutter can be reported with numbers. Off by default: the Settings app ('Performance overlay') or the
-- bindable action 'Street Legal: performance overlay'. The drawing is the slHud UI module (event slPerf); the numbers are sl/core/perf.

local M = {}

local perf = require('sl/core/perf')
local hitch = require('sl/core/hitch')
local patch = require('sl/core/patch')

local sampler = perf.new()
local sendTimer, countTimer, vramTimer, staticTimer = 0, 99, 99, 99
local counts, vram = {}, nil
local shown = false

local function on() return sl_options ~= nil and sl_options.get ~= nil and sl_options.get('slPerf') == true end

function M.toggle()
  if sl_options and sl_options.set then sl_options.set('slPerf', not on()) end
end

-- the counts are not free (every object is walked): every 2 s, and the static objects every 10
local function count(dt)
  countTimer, staticTimer = countTimer + dt, staticTimer + dt
  if countTimer < 2 then return end
  countTimer = 0
  local all = getAllVehicles and getAllVehicles() or {}
  local traffic = gameplay_traffic and gameplay_traffic.getNumOfTraffic and gameplay_traffic.getNumOfTraffic() or 0
  counts.traffic = traffic
  counts.others = math.max(0, #all - traffic - 1)                  -- (all but the traffic and the car you are in)
  counts.peds = slrrPedestrians and slrrPedestrians.getCount and slrrPedestrians.getCount() or 0
  if staticTimer >= 10 then
    staticTimer = 0
    local ok, names = pcall(function() return scenetree.findClassObjects('TSStatic') end)
    counts.statics = ok and type(names) == 'table' and #names or counts.statics
  end
end

----------------------------------------------------------------------------------------------
-- the hitch recorder (smoothness; a dev tool, off by default): sl_perf.record(true) from the console. Every frame over 50 ms is written to
-- settings/street_legal/hitches.txt with what happened in the 2 s before it (car spawns with model and ms, car builds, lot closes, the garage
-- doors) and which Street Legal extensions' onUpdate cost the most in that very frame; a garbage collection is told by the heap falling.
-- The wrappers go on the functions while it records and come off when it stops.

local PATH = '/settings/street_legal/hitches.txt'
local rec, recT, recFlush, wrapped = nil, 0, 0, {}
local clock = os.clockhp or os.clock

local function note(label, ms) if rec then hitch.event(rec, recT, label, ms) end end

-- target[key] timed: the call's ms is an event and, if cost is a name, its cost in this frame
local function wrapTimed(target, key, label, costName)
  if type(target) ~= 'table' or type(target[key]) ~= 'function' then return end
  local original = target[key]
  local fn = function(...)
    local t0 = clock()
    local r1, r2, r3 = original(...)
    local ms = (clock() - t0) * 1000
    if rec then
      if costName then hitch.cost(rec, costName, ms) end
      if label and ms >= 20 then
        local a = ...
        hitch.event(rec, recT, label .. (type(a) == 'string' and (' ' .. a) or ''), ms)
      end
    end
    return r1, r2, r3
  end
  local sv = {}          -- (patch keeps one original a key: one table for each function wrapped)
  if patch.install(target, key, fn, sv) then wrapped[#wrapped + 1] = { target, key, sv } end
end

-- target[key] noted when called (the call may sleep inside a job: no time)
local function wrapNoted(target, key, label)
  if type(target) ~= 'table' or type(target[key]) ~= 'function' then return end
  local original = target[key]
  local fn = function(...)
    local a, b = ...
    note(label .. (type(b) == 'string' and (' ' .. b) or ''))
    return original(...)
  end
  local sv = {}          -- (patch keeps one original a key: one table for each function wrapped)
  if patch.install(target, key, fn, sv) then wrapped[#wrapped + 1] = { target, key, sv } end
end

local function startRecording()
  rec, recT, recFlush = hitch.new(), 0, 0
  local timed = 0
  for name, ext in pairs(_G) do
    if type(name) == 'string' and name ~= 'sl_perf' and (name:sub(1, 3) == 'sl_' or name:sub(1, 4) == 'slrr') and type(ext) == 'table' and type(ext.onUpdate) == 'function' then
      wrapTimed(ext, 'onUpdate', nil, name .. '.onUpdate')
      timed = timed + 1
    end
  end
  if core_vehicles then wrapTimed(core_vehicles, 'spawnNewVehicle', 'spawn') end
  local ok, builder = pcall(require, 'sl/carBuilder')
  if ok and type(builder) == 'table' then
    wrapNoted(builder, 'buildCustom', 'build a car')
    wrapNoted(builder, 'buildOffer', 'build a lot car')
    wrapNoted(builder, 'spawnOwned', 'spawn an owned car')
  end
  if sl_lot then wrapNoted(sl_lot, 'close', 'the lot closes') wrapNoted(sl_lot, 'buy', 'a car is bought') end
  if slrr_garage then wrapNoted(slrr_garage, 'leave', 'the garage is left') end
  log('I', 'street_legal', 'hitch recorder on: ' .. timed .. ' extensions timed, writing ' .. PATH)
end

local function stopRecording()
  if not rec then return end
  if writeFile then pcall(writeFile, PATH, hitch.report(rec, 'Street Legal hitches')) end
  for i = #wrapped, 1, -1 do patch.restore(wrapped[i][1], wrapped[i][2], wrapped[i][3]) end
  wrapped = {}
  log('I', 'street_legal', 'hitch recorder off: ' .. rec.count .. ' hitches written to ' .. PATH)
  rec = nil
end

function M.record(on)
  if on == nil then on = rec == nil end
  if on and not rec then startRecording() elseif not on then stopRecording() end
  return rec ~= nil
end

local function recordFrame(dt)
  recT = recT + dt
  local newest = rec.count
  if next(rec.cost) then rec.seen = true end
  if not rec.seen and not rec.warned and recT > 3 then
    rec.warned = true
    log('W', 'street_legal', 'hitch recorder: no extension onUpdate was timed in 3 s (the game calls cached functions?): the per-frame costs will be missing')
  end
  local okMem, kb = pcall(collectgarbage, 'count')
  hitch.frame(rec, recT, dt, okMem and kb or nil)
  recFlush = recFlush + dt
  if rec.count ~= newest and recFlush > 10 and writeFile then      -- (the file is written every 10 s when there is something new, never inside the hitch)
    recFlush = 0
    pcall(writeFile, PATH, hitch.report(rec, 'Street Legal hitches'))
  end
end

function M.onStreetLegalStopped() stopRecording() end
function M.onExtensionUnloaded() stopRecording() end

function M.onUpdate(dtReal)
  if rec then recordFrame(dtReal or 0) end
  if not on() then
    if shown then shown = false guihooks.trigger('slPerf', { show = false }) end
    return
  end
  shown = true
  perf.add(sampler, dtReal)
  count(dtReal)
  vramTimer = vramTimer + dtReal
  if vramTimer > 2 then
    vramTimer = 0
    local ok, v = pcall(function() return Engine.Render and Engine.Render.getVRAMUsage and Engine.Render.getVRAMUsage() end)
    vram = ok and perf.vramText(v) or nil
  end
  sendTimer = sendTimer + dtReal
  if sendTimer < 0.25 then return end
  sendTimer = 0
  local lines = perf.lines(perf.read(sampler), counts, vram)
  if sl_uipush and sl_uipush.lines then for _, l in ipairs(sl_uipush.lines(3)) do lines[#lines + 1] = l end end      -- (UI smoothness: pushes and kB a second per event, screen rebuilds)
  guihooks.trigger('slPerf', { show = true, lines = lines })
end

return M
