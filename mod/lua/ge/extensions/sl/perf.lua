-- Wrench Works: Street Legal: the performance overlay (extension name: sl_perf; #49)
-- A small box top-left: frame time and fps, the worst frame of the last 10 s, video memory, and how many cars (traffic, others), pedestrians and
-- static objects are in the world, so a stutter can be reported with numbers. Off by default: the Settings app ('Performance overlay') or the
-- bindable action 'Street Legal: performance overlay'. The drawing is the slHud UI module (event slPerf); the numbers are sl/core/perf.

local M = {}

local perf = require('sl/core/perf')

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

function M.onUpdate(dtReal)
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
  guihooks.trigger('slPerf', { show = true, lines = perf.lines(perf.read(sampler), counts, vram) })
end

return M
