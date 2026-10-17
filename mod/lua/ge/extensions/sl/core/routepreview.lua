-- Street Legal: a race's route as a small 2D map (#18, F26). Pure, tested by tools/luatest.js: the route's points thinned and fitted into a
-- w x h picture (north up, equal scale on both axes, centred, with a margin), ready for the phone to draw as an SVG polyline with the start
-- and the finish marked.

local M = {}

-- at most n points of the list, evenly spaced by index, always the first and the last
function M.thin(points, n)
  n = math.max(2, n or 60)
  local out = {}
  local count = #points
  if count <= n then
    for i, p in ipairs(points) do out[i] = p end
    return out
  end
  for i = 0, n - 1 do out[#out + 1] = points[1 + math.floor(i * (count - 1) / (n - 1) + 0.5)] end
  return out
end

-- points: { { x, y } } in the world; returns { points = "x,y x,y ...", start = { x, y }, finish = { x, y }, w, h, metres, scale (metres per pixel) }
-- or nil with fewer than two points
function M.fit(points, w, h, pad)
  if type(points) ~= 'table' or #points < 2 then return nil end
  w, h, pad = w or 240, h or 140, pad or 12
  local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
  local metres = 0
  for i, p in ipairs(points) do
    x0, x1, y0, y1 = math.min(x0, p.x), math.max(x1, p.x), math.min(y0, p.y), math.max(y1, p.y)
    if i > 1 then metres = metres + math.sqrt((p.x - points[i - 1].x) ^ 2 + (p.y - points[i - 1].y) ^ 2) end
  end
  local spanX, spanY = math.max(x1 - x0, 1e-6), math.max(y1 - y0, 1e-6)
  local k = math.min((w - 2 * pad) / spanX, (h - 2 * pad) / spanY)          -- pixels per metre
  local ox = (w - spanX * k) / 2
  local oy = (h - spanY * k) / 2
  local function pt(p) return { x = math.floor((ox + (p.x - x0) * k) * 10 + 0.5) / 10, y = math.floor((h - (oy + (p.y - y0) * k)) * 10 + 0.5) / 10 } end
  local parts = {}
  for i, p in ipairs(points) do local q = pt(p) parts[i] = q.x .. ',' .. q.y end
  return { points = table.concat(parts, ' '), start = pt(points[1]), finish = pt(points[#points]), w = w, h = h, metres = math.floor(metres), scale = 1 / k }
end

return M
