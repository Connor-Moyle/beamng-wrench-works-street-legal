-- Street Legal: engine swaps in the garage (#30). Pure, tested by tools/luatest.js. An engine of the same model's own family can go in the engine
-- slot (the game's parts for that slot; no engine of another model fits: stock engine slot types are per model, 0 of 274 are shared). A swap
-- costs the engine (the shop's price), the labour, and the parts the new engine needs bolted to it; the old engine goes on the shelf.

local M = {}

M.RATE = 90                  -- $ an hour
M.MIN_HOURS, M.MAX_HOURS = 4, 14
M.NO_CROSS_MODEL = "Only this model's own engines fit its engine mounts; another model's engine does not."

function M.hours(engineValue)
  local h = M.MIN_HOURS + (tonumber(engineValue) or 0) / 5000
  return math.floor(math.max(M.MIN_HOURS, math.min(M.MAX_HOURS, h)) * 2 + 0.5) / 2
end

function M.labour(engineValue) return math.floor(M.hours(engineValue) * M.RATE / 10 + 0.5) * 10 end

-- info: { name, value, needs = { slot names }, oldName }; returns the quote and a line for the garage
function M.quote(info)
  local needs = {}
  for _, n in ipairs(info.needs or {}) do needs[#needs + 1] = tostring(n) end
  table.sort(needs)
  local q = { hours = M.hours(info.value), labour = M.labour(info.value), price = math.floor(tonumber(info.value) or 0), needs = needs, oldName = info.oldName }
  q.text = string.format('Swap: $%d labour (%.1f h)%s%s', q.labour, q.hours, info.oldName and ('. The ' .. info.oldName .. ' goes on the shelf') or '',
    #needs > 0 and ('. It needs: ' .. table.concat(needs, ', ')) or '')
  return q
end

return M
