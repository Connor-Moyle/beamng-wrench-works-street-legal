-- Street Legal: where the cars of a meet stand (A11). Pure, tested by tools/luatest.js. Meet cars used to be put on a circle round the meet's point,
-- which lay on the road: cars across the lane at any angle. They now stand in the level's painted parking bays near the meet: a bay that is free, not on
-- a road, close to the point, with a car's room round it; each car faces along its bay.

local roadspot = require('sl/core/roadspot')

local M = {}
M.RADIUS = 55              -- m from the meet's point
M.APART = 2.6              -- m between two cars

-- candidates: { { x, y, z, dx, dy, occupied } } (every bay near the meet), roads: { { x1, y1, x2, y2, half } }; n cars at most.
-- Returns { { x, y, z, dx, dy } }, nearest to the point first (fewer than n when the car park is small).
function M.pick(center, candidates, roads, n)
  local function onRoad(c)
    for _, r in ipairs(roads or {}) do
      if roadspot.segDist(c.x, c.y, c.x, c.y, r.x1, r.y1, r.x2, r.y2) < r.half + 0.8 then return true end
    end
    return false
  end
  local list = {}
  for _, c in ipairs(candidates or {}) do
    local d = math.sqrt((c.x - center.x) ^ 2 + (c.y - center.y) ^ 2)
    if not c.occupied and d <= M.RADIUS and (c.dx ~= 0 or c.dy ~= 0) and not onRoad(c) then list[#list + 1] = { c = c, d = d } end
  end
  table.sort(list, function(a, b) return a.d < b.d end)
  local out = {}
  for _, e in ipairs(list) do
    if #out >= n then break end
    local free = true
    for _, k in ipairs(out) do if math.sqrt((k.x - e.c.x) ^ 2 + (k.y - e.c.y) ^ 2) < M.APART then free = false break end end
    if free then out[#out + 1] = { x = e.c.x, y = e.c.y, z = e.c.z, dx = e.c.dx, dy = e.c.dy } end
  end
  return out
end

return M
