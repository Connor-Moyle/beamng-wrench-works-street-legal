-- Street Legal: the performance overlay's numbers (#49). Pure (tested by tools/luatest.js).
-- A sampler takes one frame time at a time (seconds of real time) and says: the average over the last second, the fps, and the worst frame of the
-- last 10 seconds. lines() turns the numbers into the overlay's text.

local M = {}

local strings = require('sl/core/strings')

M.WORST_WINDOW = 10          -- seconds the worst frame is remembered
M.AVG_WINDOW = 1             -- seconds the average is taken over

function M.new() return { t = 0, frames = {} } end

-- dt: the frame's real time in seconds
function M.add(s, dt)
  if type(dt) ~= 'number' or dt <= 0 or dt > 60 then return s end
  s.t = s.t + dt
  s.frames[#s.frames + 1] = { t = s.t, dt = dt }
  local oldest = s.t - M.WORST_WINDOW
  local keep = {}
  for _, f in ipairs(s.frames) do if f.t >= oldest then keep[#keep + 1] = f end end
  s.frames = keep
  return s
end

-- { ms, fps, worstMs }: the average frame time over the last AVG_WINDOW seconds, the fps it makes, the longest frame of the last WORST_WINDOW seconds
function M.read(s)
  local sum, n, worst = 0, 0, 0
  local from = s.t - M.AVG_WINDOW
  for i = #s.frames, 1, -1 do
    local f = s.frames[i]
    if f.dt > worst then worst = f.dt end
    if f.t > from then sum, n = sum + f.dt, n + 1 end
  end
  if n == 0 then return { ms = 0, fps = 0, worstMs = worst * 1000 } end
  local avg = sum / n
  return { ms = avg * 1000, fps = 1 / avg, worstMs = worst * 1000 }
end

-- the VRAM figure the engine gives: a number (MB) or a table with used / total (any of a few names); returns a short text, or nil
function M.vramText(v)
  if type(v) == 'number' then return string.format('%d MB', v) end
  if type(v) ~= 'table' then return nil end
  local used, total
  for _, k in ipairs({ 'used', 'usedMB', 'vramUsed', 'usage', 'current' }) do if type(v[k]) == 'number' then used = v[k] break end end
  for _, k in ipairs({ 'total', 'totalMB', 'budget', 'max', 'available' }) do if type(v[k]) == 'number' then total = v[k] break end end
  if used and total then return string.format('%d / %d MB', used, total) end
  if used then return string.format('%d MB', used) end
  return nil
end

-- the overlay's lines. c = { traffic, others (cars that are not traffic and not yours), peds, statics }, vram = text or nil
function M.lines(r, c, vram)
  c = c or {}
  local out = {
    string.format(strings.t('perf.1f_ms_d_fps'), r.ms or 0, math.floor((r.fps or 0) + 0.5)),
    string.format(strings.t('perf.worst_0f_ms_10_s'), r.worstMs or 0),
  }
  if vram then out[#out + 1] = strings.t('perf.vram_1', (vram)) end
  out[#out + 1] = string.format(strings.t('perf.cars_d_traffic_d_other'), c.traffic or 0, c.others or 0)
  out[#out + 1] = string.format(strings.t('perf.people_d_objects_d'), c.peds or 0, c.statics or 0)
  return out
end

return M
