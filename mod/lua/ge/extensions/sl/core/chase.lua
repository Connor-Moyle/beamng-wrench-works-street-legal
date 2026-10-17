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

-- a pursuit breaker (later): you pass within 6 m at speed (m/s) with a patrol inside 40 m
function M.breakerHit(distToBreaker, speed, nearestCop)
  return (distToBreaker or 1e9) < 6 and (speed or 0) > 10 and (nearestCop or 1e9) < 40
end

return M
