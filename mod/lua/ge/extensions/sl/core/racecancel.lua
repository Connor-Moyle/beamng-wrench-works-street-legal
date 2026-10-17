-- Street Legal: when a race, sprint, drag run or meet race is called off (A8). Pure, tested by tools/luatest.js.
-- Every event has a time limit and a distance it may be left by: past either one it is cancelled with a message, nobody wins or loses anything.

local M = {}

M.MAX_OFF = 350            -- metres from the route (or the strip) before the event is off
M.SLOWEST = 6              -- m/s the time limit allows along the route
M.GRACE = 150              -- seconds on top of the route's length

-- seconds an event over `metres` of route may last
function M.timeLimit(metres) return M.GRACE + (tonumber(metres) or 0) / M.SLOWEST end

-- the least distance from p to a chain of points (a polyline); points: { { x, y } }
function M.distToRoute(p, points)
  local best = math.huge
  for i = 1, #points do
    local a, b = points[i], points[i + 1] or points[i]
    local dx, dy = b.x - a.x, b.y - a.y
    local l2 = dx * dx + dy * dy
    local t = l2 > 0 and math.max(0, math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2)) or 0
    local ex, ey = a.x + dx * t - p.x, a.y + dy * t - p.y
    best = math.min(best, math.sqrt(ex * ex + ey * ey))
  end
  return best
end

-- the reason to cancel (text for the player), or nil: t seconds in, limit seconds allowed, off metres from the route or strip
function M.reason(t, limit, off, maxOff)
  if limit and (t or 0) > limit then return 'It took too long: the event is called off.' end
  if off and off > (maxOff or M.MAX_OFF) then return 'You left the route: the event is called off.' end
  return nil
end

-- distToRoute at most every `every` seconds of the event's own clock t (the whole polyline is walked each time); c is the event's cache table
function M.distCached(c, t, p, points, every)
  if c.at == nil or t - c.at >= (every or 0.25) or t < c.at then c.at, c.d = t, M.distToRoute(p, points) end
  return c.d
end

return M
