-- Street Legal: the depth of a night chase (pure rules, no engine calls; tested by tools/luatest.js). See DESIGN_police_chase.md.
-- Roadblocks from heat 2, a spike strip from heat 3, a faster cool-down when you are out of sight or under a roof, and an escape that pays by heat.

local heat = require('sl/core/heat')

local M = {}

local function lvl(level) return math.max(0, math.min(5, math.floor(tonumber(level) or 0))) end

-- the game's police variables for the phase and heat: heat.policeVars with roadblocks from level 2 and a quicker arrest as it gets hotter
local ROADBLOCK = { [2] = 0.25, [3] = 0.5, [4] = 0.75, [5] = 1 }
local ARREST_TIME = { [0] = 5, 5, 4.5, 4, 3.5, 3 }
function M.vars(ph, level)
  local v = heat.policeVars(ph, level)
  if ph ~= 'night' then return v end
  level = lvl(level)
  v.roadblockFrequency = ROADBLOCK[level] or 0
  v.arrestTime = ARREST_TIME[level]
  v.arrestRadius = 20 + 2 * level
  return v
end

-- a static ray straight up from the car that hits something within 12 m: a bridge, a car park roof, a tunnel
M.COVER_M = 12
function M.covered(rayUp) return rayUp ~= nil and rayUp < M.COVER_M end

-- how fast the evade timer runs: out of sight and covered 2, covered 1.5, out of sight 1.25
function M.evadeRate(hidden, covered)
  if hidden and covered then return 2 end
  if covered then return 1.5 end
  return hidden and 1.25 or 1
end

-- the reputation for losing them: the base times the night's boost, 5 for each roadblock passed and each strip survived
function M.escapeRep(base, ph, level, roadblocks, strips)
  return math.floor((base or 0) * heat.repBoost(ph, level) + 5 * ((roadblocks or 0) + (strips or 0)) + 0.5)
end

-- is a spike strip due: heat 3 or more, a chase on, and the gap since the last one (40 s, 25 s at heat 5) has passed
function M.stripDue(ph, level, inPursuit, sinceLast)
  if ph ~= 'night' or not inPursuit or lvl(level) < 3 then return false end
  return (sinceLast or 1e9) >= (lvl(level) >= 5 and 25 or 40)
end

-- where to put the strip: a spot on the route ahead (pts = {x,y,z} from the car on), 150-250 m along, on a straight (under 20 degrees of turn
-- over 30 m either side) and where okFn(pt) is true (not a bridge, a junction...). Returns the point and its heading, or nil.
M.STRIP_MIN, M.STRIP_MAX = 150, 250
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
function M.stripSpot(pts, okFn)
  local along, at = 0, { 0 }
  for i = 2, #pts do along = along + dist(pts[i - 1], pts[i]) at[i] = along end
  local function pointAt(d)
    for i = 2, #pts do
      if at[i] >= d then
        local t = (d - at[i - 1]) / math.max(1e-6, at[i] - at[i - 1])
        local a, b = pts[i - 1], pts[i]
        return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = (a.z or 0) + ((b.z or 0) - (a.z or 0)) * t }
      end
    end
  end
  for d = M.STRIP_MIN, math.min(M.STRIP_MAX, along - 30), 10 do
    local before, here, after = pointAt(d - 30), pointAt(d), pointAt(d + 30)
    if before and here and after then
      local ax, ay, bx, by = here.x - before.x, here.y - before.y, after.x - here.x, after.y - here.y
      local cos = (ax * bx + ay * by) / math.max(1e-6, math.sqrt(ax * ax + ay * ay) * math.sqrt(bx * bx + by * by))
      if cos >= math.cos(math.rad(20)) and (not okFn or okFn(here)) then
        return here, { x = bx, y = by }
      end
    end
  end
  return nil
end

-- why you were stopped: no fuel, a spike strip this chase, a roadblock within 40 m, two or more patrols round you; nil when none of them (and the cop count)
function M.bustCause(i)
  if i.fuelLitres and i.fuelLitres < 0.5 then return 'fuel' end
  if (i.strips or 0) > 0 then return 'strip' end
  if i.roadblockDist and i.roadblockDist < 40 then return 'roadblock' end
  if (i.cops or 0) >= 2 then return 'boxed', i.cops end
  return nil
end

-- pursuit breakers: a wall of tyres drops across the road behind you as you pass a breaker spot at speed with a patrol 25-55 m back
-- (closer and it would land on the patrol). Spots: up to n straight, wide road nodes (two links in line, radius 4 m or more) within maxD of
-- `around`, at least 300 m apart, picked in the order of the rng. nodes[name] = { pos, radius, links = { [other] = edge } } (the game's graph).
M.BREAKER_RADIUS, M.BREAKER_GAP, M.BREAKER_EVERY = 4, 300, 60
function M.breakerSpots(nodes, n, around, maxD, rng)
  local names = {}
  for name in pairs(nodes) do names[#names + 1] = name end
  table.sort(names)
  local cands = {}
  for _, name in ipairs(names) do
    local node = nodes[name]
    local pos = node.pos
    if (node.radius or 0) >= M.BREAKER_RADIUS and dist(pos, around) <= maxD and dist(pos, around) >= 60 then
      local others = {}
      for o in pairs(node.links or {}) do if nodes[o] then others[#others + 1] = nodes[o].pos end end
      if #others == 2 then
        local ax, ay, bx, by = others[1].x - pos.x, others[1].y - pos.y, others[2].x - pos.x, others[2].y - pos.y
        local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
        if la > 1 and lb > 1 and (ax * bx + ay * by) / (la * lb) < -0.95 then
          cands[#cands + 1] = { x = pos.x, y = pos.y, z = pos.z or 0, dx = bx / lb, dy = by / lb }
        end
      end
    end
  end
  local out = {}
  while #cands > 0 and #out < n do
    local c = table.remove(cands, rng:int(1, #cands))
    local far = true
    for _, o in ipairs(out) do if dist(o, c) < M.BREAKER_GAP then far = false break end end
    if far then out[#out + 1] = c end
  end
  return out
end

-- you have just passed a breaker (the distance to it was under 8 m and is growing) at speed (m/s), with the nearest patrol 25-55 m off
function M.breakerPassed(prevDist, dist, speed, nearestCop)
  return (prevDist or 1e9) < 8 and (dist or 0) > prevDist and (speed or 0) > 10 and (nearestCop or 0) > 25 and (nearestCop or 1e9) < 55
end
function M.breakerReady(sinceLast) return (sinceLast or 1e9) >= M.BREAKER_EVERY end

return M
