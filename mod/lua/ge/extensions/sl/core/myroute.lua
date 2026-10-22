-- Street Legal: my route (campaign idea #14). The player drops 4 to 8 waypoints where the car is, names the route and races it against the clock; the best time and the
-- number of runs are kept per route. No money, no reputation. Pure, no game calls: tested by tools/luatest.js.

local M = {}

local strings = require('sl/core/strings')

M.MIN_POINTS, M.MAX_POINTS = 4, 8
M.MIN_APART = 60            -- m between two neighbouring waypoints
M.MAX_LENGTH = 15000        -- m: the sum of the legs
M.MAX_ROUTES = 10           -- saved routes per map
M.REACH = 12                -- m: a waypoint is passed when the car's path comes this close
M.JUMP = 80                 -- m in one step: a teleport or a fast travel cancels the run
M.NAME_MAX = 24

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

function M.length(points)
  local sum = 0
  for i = 2, #(points or {}) do sum = sum + dist(points[i - 1], points[i]) end
  return sum
end

-- can a waypoint at p be added to points? true, or false and the reason (a strings key)
function M.canAdd(points, p)
  if #points >= M.MAX_POINTS then return false, 'myroute.full' end
  local last = points[#points]
  if last and dist(last, p) < M.MIN_APART then return false, 'myroute.too_close' end
  if last and M.length(points) + dist(last, p) > M.MAX_LENGTH then return false, 'myroute.too_long' end
  return true
end

-- one line, no control characters, not too long; empty becomes 'Route N'
function M.cleanName(name, n)
  local s = tostring(name or ''):gsub('%c', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if #s > M.NAME_MAX then s = s:sub(1, M.NAME_MAX):gsub('%s+$', '') end
  if s == '' then s = strings.t('myroute.default_name', n or 1) end
  return s
end

-- a route to keep, from the points dropped: nil and a reason when it cannot be saved. routes = the map's saved list
function M.make(points, name, routes)
  if #points < M.MIN_POINTS then return nil, 'myroute.too_few' end
  if #routes >= M.MAX_ROUTES then return nil, 'myroute.too_many' end
  local id = 1
  for _, r in ipairs(routes) do if r.id >= id then id = r.id + 1 end end
  local pts = {}
  for i, p in ipairs(points) do pts[i] = { x = p.x, y = p.y, z = p.z or 0 } end
  return { id = id, name = M.cleanName(name, id), points = pts, length = math.floor(M.length(pts)), best = 0, runs = 0, last = 0 }
end

-- ---- a run: { next = index of the waypoint to pass, t = seconds since waypoint 1, started }; waypoint 1 starts the clock
function M.newRun() return { next = 1, t = 0, started = false } end

-- the distance from point c to the segment a-b
local function segDist(a, b, c)
  local dx, dy = b.x - a.x, b.y - a.y
  local l2 = dx * dx + dy * dy
  local u = l2 > 0 and math.max(0, math.min(1, ((c.x - a.x) * dx + (c.y - a.y) * dy) / l2)) or 0
  return math.sqrt((c.x - (a.x + u * dx)) ^ 2 + (c.y - (a.y + u * dy)) ^ 2)
end

-- one step of the car from prev to now (nil prev: the first sample), dt seconds, over the route. Returns the run and an event: nil | 'start' | 'point' | 'finish' | 'cancel'
function M.step(run, route, prev, now, dt)
  local pts = route.points
  if run.started then run.t = run.t + (dt or 0) end
  if not prev then return run, nil end
  if dist(prev, now) > M.JUMP then
    if run.started then return M.newRun(), 'cancel' end
    return run, nil
  end
  local target = pts[run.next]
  if not target or segDist(prev, now, target) > M.REACH then return run, nil end
  if run.next == 1 then
    run.started, run.t, run.next = true, 0, 2
    return run, 'start'
  end
  if run.next == #pts then
    run.next = #pts + 1
    return run, 'finish'
  end
  run.next = run.next + 1
  return run, 'point'
end

-- a finished run against the route: returns the route's new record fields and whether it is a new best (the first run is a best too)
function M.record(route, seconds)
  local t = math.floor(seconds * 100 + 0.5) / 100
  local best = route.best > 0 and math.min(route.best, t) or t
  return { best = best, runs = route.runs + 1, last = t }, route.best <= 0 or t < route.best
end

function M.clock(seconds)
  if not seconds or seconds <= 0 then return '--' end
  local m = math.floor(seconds / 60)
  return string.format('%d:%05.2f', m, seconds - m * 60)
end

return M
