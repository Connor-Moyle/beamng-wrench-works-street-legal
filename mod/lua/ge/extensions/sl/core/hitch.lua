-- Street Legal: the hitch recorder's rules (smoothness). Pure, tested by tools/luatest.js. A hitch is a frame longer than THRESHOLD. The recorder keeps the
-- events of the last WINDOW seconds (a spawn with its model and ms, a lot build, a weather update ...) and the milliseconds each part spent in the
-- current frame; when a frame is a hitch it writes what happened just before and which parts of the mod cost the most in that frame.

local M = {}

M.THRESHOLD = 0.05          -- s: a frame longer than this is a hitch
M.WINDOW = 2                -- s of events kept before a hitch
M.GC_DROP = 1024            -- KB: the heap falling by this much between two frames is a garbage collection
M.TOP = 4                   -- parts listed per hitch

function M.new() return { events = {}, cost = {}, hitches = {}, count = 0, lastMem = nil, t = 0 } end

-- something happened at time t: text (and ms when it took a measured time)
function M.event(h, t, text, ms)
  h.events[#h.events + 1] = { t = t, text = text, ms = ms }
  local keep = {}
  for _, e in ipairs(h.events) do if e.t >= t - M.WINDOW - 1 then keep[#keep + 1] = e end end
  h.events = keep
end

-- ms spent by a named part in this frame (added up; cleared by M.frame)
function M.cost(h, name, ms) h.cost[name] = (h.cost[name] or 0) + ms end

-- the frame is over: dt seconds, the heap in KB. Returns the text block when it was a hitch (also kept in h.hitches), else nil.
function M.frame(h, t, dt, memKb)
  h.t = t
  local drop = h.lastMem and memKb and (h.lastMem - memKb) or 0
  h.lastMem = memKb or h.lastMem
  local out
  if dt > M.THRESHOLD then
    local lines = { string.format('t=%.1fs frame %.0f ms%s', t, dt * 1000, drop >= M.GC_DROP and string.format(', a garbage collection freed %.1f MB', drop / 1024) or '') }
    for _, e in ipairs(h.events) do
      if e.t >= t - dt - M.WINDOW and e.t <= t then
        lines[#lines + 1] = string.format('  %+.2fs %s%s', e.t - t, e.text, e.ms and string.format(' (%.0f ms)', e.ms) or '')
      end
    end
    local costs = {}
    for name, ms in pairs(h.cost) do costs[#costs + 1] = { name = name, ms = ms } end
    table.sort(costs, function(a, b) return a.ms > b.ms or (a.ms == b.ms and a.name < b.name) end)
    for i = 1, math.min(M.TOP, #costs) do
      if costs[i].ms >= 1 then lines[#lines + 1] = string.format('  in this frame: %s %.1f ms', costs[i].name, costs[i].ms) end
    end
    out = table.concat(lines, '\n')
    h.count = h.count + 1
    h.hitches[#h.hitches + 1] = out
    if #h.hitches > 400 then table.remove(h.hitches, 1) end
  end
  h.cost = {}
  return out
end

-- the file's text: a header, then every hitch
function M.report(h, header)
  return (header or 'Street Legal hitches') .. string.format('\n%d frames over %.0f ms\n\n', h.count, M.THRESHOLD * 1000) .. table.concat(h.hitches, '\n\n') .. '\n'
end

return M
