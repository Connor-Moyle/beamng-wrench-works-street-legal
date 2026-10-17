-- Street Legal: pushes to the browser side with a counter (extension name: sl_uipush; UI smoothness). sl_uipush.push(name, data, opts) is guihooks.trigger with:
--   opts.dedupe = true   the same payload as the last one for this event is not sent again (nothing changed: no serialise on the browser side, no redraw)
--   opts.minInterval = s no faster than this; the newest payload held back is sent as soon as the time is up
-- Every push and every skipped one is counted (sl/core/uistats) for the performance overlay (sl_perf adds sl_uipush.lines()). Without this extension callers fall back to a
-- plain guihooks.trigger (see sl_uipush_call in their files).

local M = {}

local uistats = require('sl/core/uistats')

local stats = uistats.new()
local last, lastSent, pending = {}, {}, {}
local jsReports = {}                          -- what the browser modules say about themselves: { phone = { rebuilds, skips }, ... }

local function send(name, data, opts, now)
  local str = jsonEncode and jsonEncode(data) or nil              -- (needed to compare, and for the size)
  if opts.dedupe and str ~= nil and str == last[name] then
    uistats.record(stats, name, 0, now, false)
    return false
  end
  last[name], lastSent[name] = str, now
  guihooks.trigger(name, data)
  uistats.record(stats, name, str and #str or 0, now, true)
  return true
end

function M.push(name, data, opts)
  opts = opts or {}
  local now = os.clock()
  if opts.minInterval and now - (lastSent[name] or -1e9) < opts.minInterval then
    pending[name] = { data = data, opts = opts }                  -- (the newest one replaces an older one held back)
    return false
  end
  pending[name] = nil
  return send(name, data, opts, now)
end

function M.onUpdate()
  if not next(pending) then return end
  local now = os.clock()
  for name, p in pairs(pending) do
    if now - (lastSent[name] or -1e9) >= (p.opts.minInterval or 0) then
      pending[name] = nil
      send(name, p.data, p.opts, now)
    end
  end
end

-- the overlay's lines
function M.lines(max)
  local out = uistats.lines(stats, os.clock(), max or 3)
  local parts = {}
  for k, v in pairs(jsReports) do parts[#parts + 1] = string.format('%s %d rebuilds, %d skipped', k, v.rebuilds or 0, v.skips or 0) end
  table.sort(parts)
  if #parts > 0 then out[#out + 1] = '  screens (5 s): ' .. table.concat(parts, '; ') end
  return out
end

function M.stats() return uistats.rates(stats, os.clock()), jsReports end

-- a browser module reports its own work every few seconds: how many times it rebuilt its screen and how many rebuilds it skipped as unchanged
function M.js(module, rebuilds, skips) jsReports[tostring(module)] = { rebuilds = tonumber(rebuilds) or 0, skips = tonumber(skips) or 0 } end

function M.reset() stats, last, lastSent, pending, jsReports = uistats.new(), {}, {}, {}, {} end
function M.onStreetLegalStopped() M.reset() end

return M
