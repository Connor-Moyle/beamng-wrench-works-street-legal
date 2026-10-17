-- Street Legal: how much the UI is told (UI smoothness). Pure, tested by tools/luatest.js. Every push of an event to the browser side (guihooks.trigger) costs the game a
-- serialise and the browser a parse and usually a redraw; this keeps a short window of pushes per event so the performance overlay can show pushes a second and kilobytes
-- a second for each, and says how many were skipped (the same payload again, or too soon).

local M = {}

M.WINDOW = 5          -- seconds the rates are taken over

function M.new() return { names = {} } end

local function prune(e, now)
  local cut = now - M.WINDOW
  local i = 1
  while e.t[i] and e.t[i] < cut do i = i + 1 end
  if i > 1 then
    local n = #e.t
    for k = 1, n do e.t[k], e.b[k], e.s[k] = e.t[k + i - 1], e.b[k + i - 1], e.s[k + i - 1] end
  end
end

-- one push (sent = true, bytes = its size) or one that was held back (sent = false)
function M.record(stats, name, bytes, now, sent)
  local e = stats.names[name]
  if not e then e = { t = {}, b = {}, s = {}, total = 0, totalBytes = 0, totalSkipped = 0 } stats.names[name] = e end
  e.t[#e.t + 1], e.b[#e.b + 1], e.s[#e.s + 1] = now, sent and (bytes or 0) or 0, sent and 1 or 0
  if sent then e.total, e.totalBytes = e.total + 1, e.totalBytes + (bytes or 0) else e.totalSkipped = e.totalSkipped + 1 end
  prune(e, now)
end

-- { { name, perSec, kbPerSec, skippedPerSec, total, totalSkipped } } by bytes, the most first
function M.rates(stats, now)
  local out = {}
  for name, e in pairs(stats.names) do
    prune(e, now)
    local sent, bytes, skipped = 0, 0, 0
    for i = 1, #e.t do
      if e.s[i] == 1 then sent, bytes = sent + 1, bytes + e.b[i] else skipped = skipped + 1 end
    end
    local span = math.max(1, math.min(M.WINDOW, e.t[1] and (now - e.t[1]) or 1))
    out[#out + 1] = { name = name, perSec = sent / span, kbPerSec = bytes / 1024 / span, skippedPerSec = skipped / span, total = e.total, totalSkipped = e.totalSkipped }
  end
  table.sort(out, function(a, b) if a.kbPerSec ~= b.kbPerSec then return a.kbPerSec > b.kbPerSec end return a.name < b.name end)
  return out
end

-- the overlay's lines: the busiest events (up to max), one line each, and a total
function M.lines(stats, now, max)
  local r, out, tp, tk = M.rates(stats, now), {}, 0, 0
  for _, x in ipairs(r) do tp, tk = tp + x.perSec, tk + x.kbPerSec end
  if #r == 0 then return out end
  out[1] = string.format('UI %.1f pushes/s, %.1f kB/s', tp, tk)
  for i = 1, math.min(max or 3, #r) do
    local x = r[i]
    out[#out + 1] = string.format('  %s %.1f/s %.1f kB/s%s', x.name, x.perSec, x.kbPerSec, x.skippedPerSec >= 0.5 and string.format(' (-%.0f/s same)', x.skippedPerSec) or '')
  end
  return out
end

return M
