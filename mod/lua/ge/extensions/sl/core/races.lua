-- Street Legal: the career's own street races (W3): where a sprint starts, where it goes, and how the two cars
-- line up. Pure rules over a plain navgraph, no game calls: everything here is tested outside the game.
--
-- nodes[name] = { pos = { x, y, z }, radius = metres (half the road width), links = { [otherName] = linkData } }
-- (links are symmetric). A position is { x, y, z }; a direction is a unit { x, y }.

local M = {}

M.WIDE = 3.5          -- m: a node this wide takes two cars side by side
M.RUN = 150           -- m of straight road a start line needs ahead of it
M.BEND = 12           -- degrees the heading may drift over that run
M.MIN_LEN, M.MAX_LEN = 1500, 4000   -- m along the route
M.GAP = 3.2           -- m between the two cars on the line
M.GOAL_RADIUS = 10    -- m: within this of the goal is finished
M.BEHIND_S = 60       -- s the second car has after the first is in

local atan2 = math.atan2 or math.atan

function M.dist2d(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

function M.degree(nodes, name)
  local n = 0
  for _ in pairs(nodes[name].links) do n = n + 1 end
  return n
end

local function heading(a, b) return math.deg(atan2(b.y - a.y, b.x - a.x)) end
local function turn(h1, h2) return math.abs((h2 - h1 + 540) % 360 - 180) end   -- 0..180

local function unitDir(a, b)
  local d = M.dist2d(a, b)
  if d < 1e-6 then return nil end
  return { x = (b.x - a.x) / d, y = (b.y - a.y) / d }
end

-- along the chain from name through nextName: over junctions and dead ends the last edge counts, a bend ends
-- it before. Returns the length walked and the node reached.
function M.straightRun(nodes, name, nextName)
  local first = heading(nodes[name].pos, nodes[nextName].pos)
  local seen, len, prev, cur = { [name] = true }, 0, name, nextName
  while true do
    len = len + M.dist2d(nodes[prev].pos, nodes[cur].pos)
    seen[cur] = true
    if M.degree(nodes, cur) ~= 2 then return len, cur end
    local nxt
    for other in pairs(nodes[cur].links) do if other ~= prev then nxt = other end end
    if not nxt or seen[nxt] or turn(first, heading(nodes[cur].pos, nodes[nxt].pos)) > M.BEND then return len, cur end
    prev, cur = cur, nxt
  end
end

local function sortedNames(nodes)
  local names = {}
  for name in pairs(nodes) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- up to count start lines on wide roads with a straight run ahead, no two within minApart metres
function M.pickStarts(nodes, rng, count, minApart)
  local cands = {}
  for _, name in ipairs(sortedNames(nodes)) do
    local n = nodes[name]
    if n.radius >= M.WIDE then
      local links = {}
      for other in pairs(n.links) do links[#links + 1] = other end
      table.sort(links)
      for _, other in ipairs(links) do
        if M.straightRun(nodes, name, other) >= M.RUN then cands[#cands + 1] = { node = name, next = other, pos = n.pos, dir = unitDir(n.pos, nodes[other].pos) } break end
      end
    end
  end
  local out = {}
  while #out < count and #cands > 0 do
    local c = table.remove(cands, rng:int(#cands))
    local apart = true
    for _, s in ipairs(out) do if M.dist2d(s.pos, c.pos) < minApart then apart = false end end
    if apart then out[#out + 1] = c end
  end
  return out
end

function M.pathLength(nodes, path)
  local len, prev = 0, nil
  for _, name in ipairs(path) do
    local n = nodes[name]
    if n then
      if prev then len = len + M.dist2d(prev.pos, n.pos) end
      prev = n
    end
  end
  return len
end

-- a junction a route of MIN_LEN..MAX_LEN leads to; pathFn(start, goal) gives the node names along the way
function M.pickGoal(nodes, startName, pathFn, rng, tries)
  local from, cands = nodes[startName].pos, {}
  for _, name in ipairs(sortedNames(nodes)) do
    local d = M.dist2d(from, nodes[name].pos)
    if d >= 600 and d <= M.MAX_LEN and M.degree(nodes, name) >= 3 then cands[#cands + 1] = name end
  end
  for _ = 1, tries or 30 do
    if #cands == 0 then return nil end
    local goal = table.remove(cands, rng:int(#cands))
    local path = pathFn(startName, goal)
    local len = #path >= 2 and M.pathLength(nodes, path) or 0
    if len >= M.MIN_LEN and len <= M.MAX_LEN then return goal, path, len end
  end
  return nil
end

-- the player on the right of the direction of travel, the opponent on the left, both facing dir
function M.lineUp(startPos, dir, gap)
  local h = (gap or M.GAP) / 2
  local rx, ry = dir.y, -dir.x
  return { player = { pos = { x = startPos.x + rx * h, y = startPos.y + ry * h, z = startPos.z }, dir = dir },
           opponent = { pos = { x = startPos.x - rx * h, y = startPos.y - ry * h, z = startPos.z }, dir = dir } }
end

-- the way the route leaves the start: the first edge, or (ahead, metres) the direction to the point that far along the route, so a tiny first
-- edge at a junction does not decide it
function M.routeDir(nodes, path, ahead)
  if #path < 2 or not (nodes[path[1]] and nodes[path[2]]) then return nil end
  if ahead then
    local walked, prev = 0, nodes[path[1]].pos
    for i = 2, #path do
      local n = nodes[path[i]]
      if not n then break end
      walked = walked + M.dist2d(prev, n.pos)
      if walked >= ahead then return unitDir(nodes[path[1]].pos, n.pos) or unitDir(nodes[path[1]].pos, nodes[path[2]].pos) end
      prev = n.pos
    end
  end
  return unitDir(nodes[path[1]].pos, nodes[path[2]].pos)
end

-- node names along the race's real route, at most `count` of them evenly spaced, ending with the goal: the markers and the opponent's AI
-- follow these (a single destination lets the game's planner pick any way, even one that leaves the other way)
function M.waypoints(path, count)
  count = math.max(2, count or 12)
  local out = {}
  if #path == 0 then return out end
  local step = math.max(1, math.floor(#path / count))
  for i = step + 1, #path - 1, step do out[#out + 1] = path[i] end
  out[#out + 1] = path[#path]
  return out
end

-- are two cars facing the way of the route: a forward { x, y } against dir
function M.facingOk(fwd, dir, minDot)
  local l = math.sqrt(fwd.x * fwd.x + fwd.y * fwd.y)
  if l < 1e-6 then return false end
  return (fwd.x * dir.x + fwd.y * dir.y) / l >= (minDot or 0.5)
end

function M.nearGoal(pos, goalPos, radius)
  return M.dist2d(pos, goalPos) <= (radius or M.GOAL_RADIUS)
end

-- one step of the racing phase: nothing but the two positions against the goal (no navgraph, no paths).
-- done = { player = s, opponent = s } is filled in as each car gets within GOAL_RADIUS; oppPos nil = no opponent
-- left. Returns 'won' | 'lost' | nil (still racing).
function M.step(goalPos, playerPos, oppPos, t, done)
  if playerPos and not done.player and M.nearGoal(playerPos, goalPos) then done.player = t end
  if oppPos and not done.opponent and M.nearGoal(oppPos, goalPos) then done.opponent = t end
  if done.player then return (not oppPos or not done.opponent or done.player <= done.opponent) and 'won' or 'lost' end
  if done.opponent and t - done.opponent > M.BEHIND_S then return 'lost' end
  return nil
end

return M
