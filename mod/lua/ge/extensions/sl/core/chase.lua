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

-- the spot of a spike strip on the route ahead and the way the route runs there, or nil. (A call like "pts and f()" gives one value only, which once left the way nil: this one gives both or none.)
function M.stripPlan(pts, okFn)
  if not pts then return nil end
  local spot, dir = M.stripSpot(pts, okFn)
  if spot and dir then return spot, dir end
  return nil
end

-- a tick that must not fail every frame: run fn(...) under pcall; after MAX_FAILS failures in a row it is switched off (state.off) for the rest of the session. state = { fails = 0, off = false }
M.MAX_FAILS = 5
function M.guarded(state, fn, ...)
  if state.off then return false end
  local ok, err = pcall(fn, ...)
  if ok then state.fails = 0 return true end
  state.fails = state.fails + 1
  if state.fails >= M.MAX_FAILS then state.off = true end
  return false, err, state.off
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

-- ---- P1: the pursuit level follows the heat. The game's pursuit mode 1-3 (lights, more units, roadblocks); its score levels decide when it climbs on its own
M.MODE = { [0] = 1, 1, 1, 2, 2, 3 }                       -- heat level -> the mode a chase starts at
M.JOINERS = { [0] = 1, 1, 1, 2, 3, 4 }                   -- heat level -> how many of the nearest patrols join at the start
local SCORE = { 100, 500, 2000 }                           -- the game's own thresholds (gameplay/police.lua defaultScoreLevels)
function M.modeFor(level) return M.MODE[lvl(level)] end
function M.joiners(level) return M.JOINERS[lvl(level)] end
-- the score levels for the heat: at heat 5 the game climbs to the next mode at half the score, at heat 0 as it ships
function M.scoreLevels(level)
  local f = 1 - 0.1 * lvl(level)
  return { math.floor(SCORE[1] * f + 0.5), math.floor(SCORE[2] * f + 0.5), math.floor(SCORE[3] * f + 0.5) }
end
-- the n nearest of the police ids (cops: id -> distance), nearest first
function M.nearest(cops, n)
  local list = {}
  for id, d in pairs(cops or {}) do list[#list + 1] = { id = id, d = d } end
  table.sort(list, function(a, b) return a.d < b.d end)
  local out = {}
  for i = 1, math.min(n or 1, #list) do out[i] = list[i].id end
  return out
end

-- ---- P13: cops at the finish. A patrol that was near the route joins when the race ends: the chance by heat and the aggression setting, a patrol within reach
M.FINISH_REACH = 300
function M.finishChance(ph, level, aggression)
  if ph ~= 'night' then return 0 end
  return math.min(0.9, (0.1 + 0.15 * lvl(level)) * (tonumber(aggression) or 1))
end

-- ---- P3: hiding spots and the cool-down. Parked (under 1 m/s) within reach of a hide place (a garage, a fuel station's wash) and out of sight: the evade timer runs x3
M.HIDE_REACH, M.HIDE_RATE = 20, 3
M.HIDE_KINDS = { garage = true, gas = true }
function M.atHideSpot(places, pos, speed)
  if not pos or (speed or 0) > 1 then return nil end
  for _, p in pairs(places or {}) do
    if M.HIDE_KINDS[p.kind] and p.pos and dist(p.pos, pos) <= M.HIDE_REACH then return p end
  end
  return nil
end
function M.hideRate(base, hidden, atSpot) if hidden and atSpot then return math.max(base or 1, M.HIDE_RATE) end return base or 1 end
-- after an escape: 90 s in which the patrols leave you alone and the heat cools five times as fast; a repaint at night drops one level, once a night
M.COOLDOWN_S, M.COOLDOWN_COOL, M.REPAINT_DROP = 90, 5, 0.2
function M.coolingMinutes(minutes, inCooldown) return (minutes or 0) * (inCooldown and M.COOLDOWN_COOL or 1) end

-- ---- P6: radio chatter (text). An event becomes a strings.t key and its fills: the unit number, the car, the district and the heading
local HEADINGS = { 'north', 'north-east', 'east', 'south-east', 'south', 'south-west', 'west', 'north-west' }
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end      -- (LuaJIT has atan2; the test runner's Lua 5.3 has the two-argument atan)
function M.heading(vx, vy)
  if (vx or 0) == 0 and (vy or 0) == 0 then return nil end
  local a = math.deg(atan2(vx, vy))      -- 0 = north (+y), clockwise
  if a < 0 then a = a + 360 end
  return HEADINGS[math.floor((a + 22.5) / 45) % 8 + 1]
end
M.CHATTER = { start = 'police.radio_start', backup = 'police.radio_backup', lost = 'police.radio_lost', visual = 'police.radio_visual', roadblock = 'police.radio_roadblock',
              strip = 'police.radio_strip', evade = 'police.radio_evade', arrest = 'police.radio_arrest' }
-- -> key, unit, car, where, heading
function M.chatter(event, ctx)
  local key = M.CHATTER[event]
  if not key then return nil end
  ctx = ctx or {}
  return key, ctx.unit or 1, ctx.car or 'the suspect', ctx.district or 'the area', M.heading(ctx.vx, ctx.vy) or 'unknown'
end

-- ---- P4: the units by heat, from the game's own police configs (every .pc below ships in 0.40: content/vehicles scan, 2026-10-22)
M.UNITS = {
  { 'fullsize', 'vehicles/fullsize/police.pc', 0 }, { 'midsize', 'vehicles/midsize/police.pc', 0 }, { 'roamer', 'vehicles/roamer/sheriff.pc', 0 },
  { 'etkc', 'vehicles/etkc/kc6x_340_police_highway_A.pc', 3 }, { 'bastion', 'vehicles/bastion/police_v8_awd_A.pc', 3 },                 -- highway patrol from heat 3
  { 'bastion', 'vehicles/bastion/police_unmarked_v8_awd_A.pc', 4 }, { 'van', 'vehicles/van/police.pc', 4 },                           -- unmarked and the heavy unit from heat 4
}
function M.configsFor(level)
  local out = {}
  for _, u in ipairs(M.UNITS) do if lvl(level) >= u[3] then out[#out + 1] = { u[1], u[2] } end end
  return out
end

return M
