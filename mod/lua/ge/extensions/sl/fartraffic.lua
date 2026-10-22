-- Street Legal: distant background traffic at night (extension name: sl_fartraffic; design: the control repo's docs/BACKGROUND_TRAFFIC.md). THIS FILE IS THE PROBE ONLY: nothing runs unless
-- the console calls sl_fartraffic.probe(route, count). It puts moving pairs of lights on the road graph beyond the real traffic ring and draws them with one of two routes, so 80 can look at them
-- at night and measure what they cost: 'A' = the debug drawer's spheres (no objects), 'B' = a small static sphere per light moved every frame. The walker is sl/core/fartraffic (tested).

local M = {}

local F = require('sl/core/fartraffic')

local run                    -- { route, cars state, cfg, statics = { }, graph, t, single }
local SHAPE = 'art/shapes/interface/checkpoint_marker_sphere.dae'      -- the game's own sphere (a translucent marker: the colour is the shape's, a route B probe shows size and cost only)

local function graphOf()
  local ok, mp = pcall(function() return map.getMap() end)
  if not ok or type(mp) ~= 'table' or not mp.nodes then return nil end
  return { nodes = mp.nodes }
end

local function camera()
  local p = core_camera and core_camera.getPosition and core_camera.getPosition()
  local q = core_camera and core_camera.getQuat and core_camera.getQuat()
  if not p or not q then return nil end
  local f = q * vec3(0, 1, 0)
  return { x = p.x, y = p.y, z = p.z, fx = f.x, fy = f.y }
end

-- a road node about 300 m in front of the camera (within 25 degrees of where it looks) with a link: where the single probe pair starts
local function nodeAhead(graph, cam)
  local best, bestErr
  for id, n in pairs(graph.nodes) do
    local dx, dy = n.pos.x - cam.x, n.pos.y - cam.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > 250 and d < 350 and next(n.links or {}) then
      local cosA = (dx * cam.fx + dy * cam.fy) / (d * math.max(0.001, math.sqrt(cam.fx * cam.fx + cam.fy * cam.fy)))
      if cosA > 0.9 then
        local err = math.abs(d - 300)
        if not bestErr or err < bestErr then best, bestErr = id, err end
      end
    end
  end
  return best
end

local function statics(n)
  if not run.statics then run.statics = {} end
  while #run.statics < n do
    local o = createObject('TSStatic')
    o:setField('shapeName', 0, SHAPE)
    o:setField('collisionType', 0, 'None')
    o.canSave = false
    o:registerObject('slFarLight_' .. tostring(#run.statics + 1) .. '_' .. tostring(os.time()))
    run.statics[#run.statics + 1] = o
  end
end

function M.stop()
  if not run then return 'not running' end
  for _, o in ipairs(run.statics or {}) do pcall(function() o:delete() end) end
  run = nil
  return 'stopped'
end

-- sl_fartraffic.probe('A') / probe('B'): one pair about 300 m ahead of the camera along a road; probe('A', 24): 24 pairs in the ring. stop() ends it (it ends by itself after two minutes).
function M.probe(route, count)
  M.stop()
  route = (route == 'B') and 'B' or 'A'
  count = math.min(200, math.max(1, math.floor(tonumber(count) or 1)))          -- (at most 200 pairs: route B makes an object per light)
  local graph, cam = graphOf(), camera()
  if not graph or not cam then return 'no road graph or camera' end
  local cfg = F.defaults()
  local state = F.newState(7)
  local single = count == 1
  if single then
    local id = nodeAhead(graph, cam)
    if not id then return 'no road node about 300 m ahead: turn the camera along a road' end
    local other
    for oid in pairs(graph.nodes[id].links) do other = oid break end
    local n1, n2 = graph.nodes[id], graph.nodes[other]
    local len = math.sqrt((n2.pos.x - n1.pos.x) ^ 2 + (n2.pos.y - n1.pos.y) ^ 2)
    state.cars[1] = { id = 1, a = id, b = other, t = 0, len = len, speed = 15, lane = 1.8, edge = graph.nodes[id].links[other] }
    cfg.inner, cfg.outer, cfg.max, cfg.spawnEvery = 100, 1500, 0, 1e9           -- (one fixed pair: it stays however near it gets, and nothing else spawns)
  else
    cfg.max = count
  end
  run = { route = route, state = state, cfg = cfg, graph = graph, t = 0, single = single }
  local tv = ''
  pcall(function()
    local v = gameplay_traffic.getTrafficVars()
    local keys = {}
    for k, val in pairs(v) do if type(val) ~= 'table' then keys[#keys + 1] = k .. '=' .. tostring(val) end end
    table.sort(keys)
    tv = table.concat(keys, ' ')
  end)
  local text = string.format('far traffic probe: route %s, %d pair(s), %d nodes; traffic vars: %s', route, count, (function() local n = 0 for _ in pairs(graph.nodes) do n = n + 1 end return n end)(), tv)
  log('I', 'sl_fartraffic', text)
  return text
end

local function step(dt)
  if not run then return end
  run.t = run.t + dt
  if run.t > 120 then M.stop() return end
  local cam = camera()
  if not cam then return end
  F.step(run.state, run.graph, cam, dt, run.cfg)
  local lights = F.lights(run.state, run.graph, cam, run.cfg)
  if run.route == 'A' then
    for _, l in ipairs(lights) do
      debugDrawer:drawSphere(vec3(l.x, l.y, l.z), l.size, ColorF(l.r, l.g, l.b, l.a))
      debugDrawer:drawSphere(vec3(l.x, l.y, l.z), l.size * 3, ColorF(l.r, l.g, l.b, l.a * 0.15))       -- a faint halo
    end
  else
    statics(#lights)
    for i, o in ipairs(run.statics) do
      local l = lights[i]
      if l then
        o:setPosition(vec3(l.x, l.y, l.z))
        o:setScale(vec3(l.size * 2, l.size * 2, l.size * 2))
        o.hidden = false
      else
        o.hidden = true
      end
    end
  end
end

-- an error in a step stops the probe (it would throw every frame for two minutes, with the route B statics alive)
function M.onUpdate(dt)
  if not run then return end
  local ok, err = pcall(step, dt)
  if not ok then
    pcall(log, 'E', 'sl_fartraffic', 'probe stopped after an error: ' .. tostring(err))
    M.stop()
  end
end

function M.onClientEndMission() M.stop() end
function M.onStreetLegalStopped() M.stop() end

return M
