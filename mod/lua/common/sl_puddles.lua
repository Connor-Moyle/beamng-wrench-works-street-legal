-- Street Legal: puddles and the wheels that drive through them (shared by the game side, sl/weather.lua, and the car's own Lua, vehicle extension slCar).
-- Pure, tested by tools/luatest.js. A puddle p = { x, y, sx, sy, dx, dy, k }: centre, size across (sx) and along (sy) its direction (dx, dy), k the size factor
-- while it grows or dries. The plane's own x axis is across: (dy, -dx); its y axis is along: (dx, dy).

local M = {}

M.AQUA_FROM_KMH, M.AQUA_FULL_KMH = 80, 120      -- a wheel starts to float above this speed in a puddle, and is mostly afloat at the second
M.MIN_WHEEL_GRIP = 0.15

-- 0 outside the puddle, up to 1 well inside (the water is shallow at the rim and deep across most of the middle)
function M.depth(p, x, y)
  local ox, oy = x - p.x, y - p.y
  local k = p.k or 1
  local u = (ox * p.dy - oy * p.dx) / math.max(0.05, p.sx * k * 0.5)
  local v = (ox * p.dx + oy * p.dy) / math.max(0.05, p.sy * k * 0.5)
  local r = math.sqrt(u * u + v * v)
  if r >= 1 then return 0 end
  return math.min(1, (1 - r) * 2.5)
end

function M.deepest(list, x, y)
  local best = 0
  for _, p in ipairs(list or {}) do
    local d = M.depth(p, x, y)
    if d > best then best = d end
  end
  return best
end

-- the grip factor of one wheel in water of this depth at this speed: a little less in the wet, almost none once it aquaplanes
function M.wheelGrip(speedKmh, depth)
  depth, speedKmh = math.max(0, math.min(1, depth or 0)), math.max(0, speedKmh or 0)
  if depth <= 0 then return 1 end
  local aqua = math.max(0, math.min(1, (speedKmh - M.AQUA_FROM_KMH) / (M.AQUA_FULL_KMH - M.AQUA_FROM_KMH)))
  return math.max(M.MIN_WHEEL_GRIP, 1 - 0.15 * depth - 0.7 * aqua * depth)
end

-- the push back on a wheel ploughing through water (newtons): more with depth and speed, capped
function M.drag(speedMs, depth)
  depth, speedMs = math.max(0, math.min(1, depth or 0)), math.max(0, speedMs or 0)
  if depth <= 0 or speedMs < 1 then return 0 end
  return math.min(500, depth * (80 + 9 * speedMs))
end

-- the spray a wheel throws in a puddle (0..1) and the fine mist of a wet road (0..1)
function M.splash(speedMs, depth)
  if (depth or 0) < 0.05 then return 0 end
  return math.max(0, math.min(1, (speedMs or 0) / 18)) * math.min(1, 0.4 + (depth or 0))
end
function M.mist(wetness, speedMs)
  return math.max(0, math.min(1, ((wetness or 0) - 0.3) / 0.7)) * math.max(0, math.min(1, ((speedMs or 0) - 6) / 20))
end

return M
