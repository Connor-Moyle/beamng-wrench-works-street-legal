-- Street Legal: distant background traffic at night (the control repo's docs/BACKGROUND_TRAFFIC.md). Pure, no game calls: tested by tools/luatest.js.
-- Cars that exist only as a pair of lights, walking the road graph beyond the real traffic ring. The graph has the shape of map.getMap(): graph.nodes[id] = { pos = {x, y, z}, radius,
-- links = { [otherId] = edge } } with edge = { drivability, speedLimit, oneWay, lanes, inNode } (a one-way edge runs from its inNode to the other end: unverified in the game).
-- The state holds the cars; step() moves them and keeps the ring filled; lights() turns them into the points a sprite route draws.

local rngLib = require('sl/core/rng')

local M = {}

function M.defaults()
  return {
    inner = 300,           -- m: no fake car nearer than this to the camera (the real traffic ring)
    outer = 700,           -- m: none further than this
    fadeIn = 60,           -- m over which a car fades in beyond the inner edge
    fadeOut = 100,         -- m over which it fades out before the outer edge
    max = 24,              -- cars
    lightHalf = 0.75,      -- m: half the distance between the two lights of a pair
    lightZ = 0.7,          -- m above the road
    spawnEvery = 0.5,      -- s between spawn attempts
  }
end

-- the spacing between cars in one direction by the kind of road, m; nil: no cars on it
M.SPACING = { trunk = 115, side = 375 }

local function len2(dx, dy) return math.sqrt(dx * dx + dy * dy) end

-- the kind of an edge from the radius of its ends and its lanes: 'trunk' (wide, or one-way, or more than two lanes), 'side', or nil (a track or a dead-end stub)
function M.roadClass(edge, r1, r2)
  local radius = ((r1 or 2) + (r2 or 2)) * 0.5
  local lanes = tostring(edge and edge.lanes or '')
  if edge and edge.drivability and edge.drivability < 0.2 then return nil end
  if radius < 1.6 then return nil end
  if (edge and edge.oneWay) or #lanes > 2 or radius >= 4 then return 'trunk' end
  return 'side'
end

-- the speed of an edge in m/s: the graph's own limit within 5 to 30, else from the road class
function M.edgeSpeed(edge, class)
  local v = tonumber(edge and edge.speedLimit)
  if v and v > 0 then return math.max(5, math.min(30, v)) end
  return class == 'trunk' and 22 or 13
end

function M.newState(seed) return { rng = rngLib.new(seed or 1), cars = {}, t = 0, spawnT = 0, nextId = 1 } end

-- the two ends of an edge as the car walks it (a -> b): a one-way edge only runs from its inNode
local function ends(graph, n1, n2, edge, rng)
  if edge.oneWay and edge.inNode then
    local a = edge.inNode
    return a, (a == n1) and n2 or n1
  end
  if rng:int(1, 2) == 1 then return n1, n2 end
  return n2, n1
end

local function node(graph, id) return graph.nodes[id] end

local function carPos(graph, car)
  local na, nb = node(graph, car.a), node(graph, car.b)
  local k = car.len > 0 and car.t / car.len or 0
  local ax, ay, az = na.pos.x, na.pos.y, na.pos.z
  local dx, dy = nb.pos.x - ax, nb.pos.y - ay
  local l = len2(dx, dy)
  if l < 0.001 then return ax, ay, az, 1, 0 end
  local ux, uy = dx / l, dy / l
  local rx, ry = uy, -ux                                        -- right of the direction of travel
  return ax + dx * k + rx * car.lane, ay + dy * k + ry * car.lane, az + (nb.pos.z - az) * k, ux, uy
end

-- how many cars of this direction are already within `spacing` of the new car's place on the edge
local function crowded(state, graph, a, b, spacing, t)
  for _, c in ipairs(state.cars) do
    if c.a == a and c.b == b and math.abs(c.t - t) < spacing then return true end
  end
  return false
end

local function trySpawn(state, graph, cam, cfg)
  local rng = state.rng
  -- the candidates: edges whose middle is in the ring (a few hundred at most on a normal map)
  local cand, n = state.cand or {}, 0
  for id1, n1 in pairs(graph.nodes) do
    for id2, edge in pairs(n1.links or {}) do
      if tostring(id1) < tostring(id2) or not (graph.nodes[id2].links and graph.nodes[id2].links[id1]) then
        local n2 = graph.nodes[id2]
        if n2 then
          local mx, my = (n1.pos.x + n2.pos.x) * 0.5, (n1.pos.y + n2.pos.y) * 0.5
          local d = len2(mx - cam.x, my - cam.y)
          if d > cfg.inner + 20 and d < cfg.outer - 40 then
            -- the edge must keep out of the real ring along its whole length: both ends beyond the inner edge
            if len2(n1.pos.x - cam.x, n1.pos.y - cam.y) > cfg.inner and len2(n2.pos.x - cam.x, n2.pos.y - cam.y) > cfg.inner then
              n = n + 1
              cand[n] = { id1, id2, edge }
            end
          end
        end
      end
    end
  end
  for i = n + 1, #cand do cand[i] = nil end
  state.cand = cand
  if n == 0 then return false end
  for _ = 1, 6 do
    local c = cand[rng:int(1, n)]
    local n1, n2 = node(graph, c[1]), node(graph, c[2])
    local class = M.roadClass(c[3], n1.radius, n2.radius)
    local spacing = class and M.SPACING[class]
    if spacing then
      local a, b = ends(graph, c[1], c[2], c[3], rng)
      local na, nb = node(graph, a), node(graph, b)
      local l = len2(nb.pos.x - na.pos.x, nb.pos.y - na.pos.y)
      local t = rng:float() * l
      if l > 20 and not crowded(state, graph, a, b, spacing, t) then
        local speed = M.edgeSpeed(c[3], class) * (0.8 + 0.25 * rng:float())
        local lane = c[3].oneWay and 0 or math.min(2.2, (n1.radius or 3) * 0.5)
        state.cars[#state.cars + 1] = { id = state.nextId, a = a, b = b, t = t, len = l, speed = speed, lane = lane, edge = c[3] }
        state.nextId = state.nextId + 1
        return true
      end
    end
  end
  return false
end

-- the next edge at a junction: weighted by drivability, not back where it came from unless it is a dead end; returns the node to go to and its edge, or nil
local function nextLink(graph, car, rng)
  local here = node(graph, car.b)
  local opts, total = {}, 0
  for id, edge in pairs(here.links or {}) do
    if id ~= car.a and graph.nodes[id] and not (edge.oneWay and edge.inNode and edge.inNode ~= car.b) then
      local w = math.max(0.05, tonumber(edge.drivability) or 1)
      opts[#opts + 1] = { id, edge, w }
      total = total + w
    end
  end
  table.sort(opts, function(x, y) return tostring(x[1]) < tostring(y[1]) end)       -- (pairs order is not stable: the same seed must give the same cars)
  if #opts == 0 then
    local back = here.links and here.links[car.a]
    if back and not (back.oneWay and back.inNode and back.inNode ~= car.b) then return car.a, back end
    return nil
  end
  local r = rng:float() * total
  for _, o in ipairs(opts) do
    r = r - o[3]
    if r <= 0 then return o[1], o[2] end
  end
  return opts[#opts][1], opts[#opts][2]
end

-- one step of dt seconds: the cars move (and turn at junctions), the ones out of the ring go, the ring is topped up. cam = { x, y }
function M.step(state, graph, cam, dt, cfg)
  cfg = cfg or M.defaults()
  state.t = state.t + dt
  local keep = {}
  for _, car in ipairs(state.cars) do
    car.t = car.t + car.speed * dt
    local alive = true
    while alive and car.t >= car.len do
      local rest = car.t - car.len
      local nb, edge = nextLink(graph, car, state.rng)
      if not nb then alive = false break end
      local na, nbn = node(graph, car.b), node(graph, nb)
      car.a, car.b, car.edge = car.b, nb, edge
      car.len = len2(nbn.pos.x - na.pos.x, nbn.pos.y - na.pos.y)
      car.t = rest
      if car.len < 1 then alive = false end
      car.lane = edge.oneWay and 0 or math.min(2.2, (na.radius or 3) * 0.5)
    end
    if alive then
      local x, y = carPos(graph, car)
      local d = len2(x - cam.x, y - cam.y)
      if d >= cfg.inner * 0.9 and d <= cfg.outer + 100 then keep[#keep + 1] = car end
    end
  end
  state.cars = keep
  state.spawnT = state.spawnT + dt
  if state.spawnT >= cfg.spawnEvery then
    state.spawnT = 0
    if #state.cars < cfg.max then trySpawn(state, graph, cam, cfg) end
  end
end

-- the fade of a car at distance d from the camera: 0 at the inner edge rising to 1 over fadeIn, 1 in the middle, down to 0 at the outer edge over fadeOut
function M.alpha(d, cfg)
  cfg = cfg or M.defaults()
  local a = math.min(1, math.max(0, (d - cfg.inner) / cfg.fadeIn))
  local b = math.min(1, math.max(0, (cfg.outer - d) / cfg.fadeOut))
  return math.min(a, b)
end

-- the lights to draw: { { x, y, z, r, g, b, a, size } }: two per car, white toward the camera and red away from it. cam = { x, y, z }
function M.lights(state, graph, cam, cfg)
  cfg = cfg or M.defaults()
  local out = {}
  for _, car in ipairs(state.cars) do
    local x, y, z, ux, uy = carPos(graph, car)
    local dx, dy = cam.x - x, cam.y - y
    local d = len2(dx, dy)
    local a = M.alpha(d, cfg)
    if a > 0.02 then
      local toward = (ux * dx + uy * dy) > 0
      local r, g, b = 1, 0.95, 0.8
      if not toward then r, g, b = 1, 0.1, 0.05 end
      local size = math.max(0.15, d * 0.0015)
      local rx, ry = uy, -ux
      for s = -1, 1, 2 do
        out[#out + 1] = { x = x + rx * cfg.lightHalf * s, y = y + ry * cfg.lightHalf * s, z = z + cfg.lightZ, r = r, g = g, b = b, a = a, size = size, car = car.id }
      end
    end
  end
  return out
end

return M
