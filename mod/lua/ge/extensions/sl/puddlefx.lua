-- Street Legal: puddles and what the wheels do in them (extension name: sl_puddlefx; part of the weather, #45).
-- While the roads are wet (sl_weather's wetness) thin planes of translucent water stand on flat road spots round the player: each plane is a small grid whose
-- corners are dropped onto the surface (a ray per corner), so it follows the slope, the camber and the dips like a decal. They fade in as the rain lasts and
-- shrink as the road dries; only the ones near the player exist, the rest are deleted behind him. The car's own Lua (vehicle extension slCar) is told which
-- puddles are near; a wheel inside one gets drag and, fast enough, aquaplanes (sl_puddles has the rules), and asks back for spray (a particle emitter at the
-- wheel, the game's own water-wheels one), the fine mist of a wet road, and a short-lived darker wet trail. Each part is behind a flag (M.flags / M.flag).

local M = {}

local rules = require('sl/core/weather')
local pr = require('sl_puddles')

local TAG = 'sl_puddlefx'
M.flags = { warp = true, splash = true, mist = true, physics = true, trail = true, ripples = true, shimmer = true }

local MATERIALS = '/art/street_legal/main.materials.json'
local MATERIAL = 'sl_puddle'          -- translucent, alpha from its opacity map (the soft oval), shiny and dark
local RIPPLE_MATERIAL = 'sl_ripple'   -- a sprite sheet of 8 growing, fading rings that the material plays by itself (animFlags 16, sequence): the shape's UV shows one frame
local SHAPES = '/temp/street_legal/shapes/'
local GRID = 5                        -- corners across a puddle's grid
local PUDDLE_RADIUS = { 8, 70 }       -- puddles stand between these distances from the player
local FORGET_AT = 95                  -- ... and are deleted beyond this
local EMITTER = 'BNGP_50'             -- the game's own water-on-wheels emitter (the splash a wheel throws in a lake)
local MAX_TRAILS, TRAIL_LIFE = 12, 5

local puddles = {}                    -- { x, y, z, sx, sy, dx, dy, born, damp, id, obj, k }
local trails = {}                     -- { obj, born, dx, dy }
local lastTrail = {}                  -- the last trail put down per wheel index: { x, y }
local emitters = {}                   -- the four particle emitters, reused
local counter = 0
local placeTimer, meshTimer, feedTimer, trailTimer = 0, 0, 0, 0
local debugPuddle
local sentEmpty = true
local stats = { tries = 0, noSurface = 0, notFlat = 0, noRoad = 0, placed = 0, shown = 0, fxCalls = 0, splashOn = 0, mistOn = 0, trails = 0, wheelsIn = 0, ripples = 0 }
local lastStatsLog = 0
local logged = {}

local function once(key, text) if not logged[key] then logged[key] = true log('I', TAG, text) end end

----------------------------------------------------------------------------------------------
-- the ground

local function surfaceZ(x, y, zTop)
  local ok, z = pcall(function() return be:getSurfaceHeightBelow(vec3(x, y, zTop)) end)
  if ok and type(z) == 'number' and z > -1e5 then return z end
end

-- the height of what is there to drive on: a ray down onto the static geometry (as the flares do), else the surface height
local function groundZ(x, y, zTop)
  local ok, d = pcall(function() return castRayStatic(vec3(x, y, zTop), vec3(0, 0, -1), 40) end)
  if ok and type(d) == 'number' and d < 40 then return zTop - d end
  return surfaceZ(x, y, zTop)
end

-- a flat spot on a road: the ground under four points round it is level, and a road runs through it
local function roadSpot(x, y, zTop)
  stats.tries = stats.tries + 1
  local z = groundZ(x, y, zTop)
  if not z then stats.noSurface = stats.noSurface + 1 return nil end
  for _, d in ipairs({ { 0.9, 0 }, { -0.9, 0 }, { 0, 0.9 }, { 0, -0.9 } }) do
    local zz = groundZ(x + d[1], y + d[2], zTop)
    if not zz or math.abs(zz - z) > 0.12 then stats.notFlat = stats.notFlat + 1 return nil end
  end
  local ok, n1, _, dist = pcall(function() return map.findClosestRoad(vec3(x, y, z), 25) end)
  if not (ok and n1) then stats.noRoad = stats.noRoad + 1 return nil end
  local radius = 3
  pcall(function() radius = map.getMap().nodes[n1].radius or 3 end)
  if dist > math.max(2, radius * 0.8) then stats.noRoad = stats.noRoad + 1 return nil end
  return z
end

----------------------------------------------------------------------------------------------
-- the model: a GRID x GRID mesh of unit size (a thin slab: a top and a bottom skin), written once per puddle with the ground heights of its corners

-- heights: GRID * GRID numbers, row by row from the corner (-0.5, -0.5): how far the ground there is above the puddle's centre
local function gridDae(heights, opts)
  local n = opts and opts.n or GRID
  local material = opts and opts.material or MATERIAL
  local uMax = opts and opts.uMax or 1
  local pos, uv = {}, {}
  for layer = 0, 1 do
    for iy = 0, n - 1 do
      for ix = 0, n - 1 do
        pos[#pos + 1] = string.format('%.3f %.3f %.3f', -0.5 + ix / (n - 1), -0.5 + iy / (n - 1), (heights and heights[iy * n + ix + 1] or 0) + layer * 0.01)
      end
    end
  end
  for iy = 0, n - 1 do for ix = 0, n - 1 do uv[#uv + 1] = string.format('%.4f %.3f', uMax * ix / (n - 1), iy / (n - 1)) end end
  local tris, count = {}, 0
  local function tri(a, b, c, normal)
    tris[#tris + 1] = string.format('%d %d %d %d %d %d %d %d %d', a[1], normal, a[2], b[1], normal, b[2], c[1], normal, c[2])
    count = count + 1
  end
  local top = n * n
  for iy = 0, n - 2 do
    for ix = 0, n - 2 do
      local i = iy * n + ix
      -- the top skin faces up (counter-clockwise seen from above), the bottom one down
      tri({ top + i, i }, { top + i + 1, i + 1 }, { top + i + n + 1, i + n + 1 }, 0)
      tri({ top + i, i }, { top + i + n + 1, i + n + 1 }, { top + i + n, i + n }, 0)
      tri({ i, i }, { i + n + 1, i + n + 1 }, { i + 1, i + 1 }, 1)
      tri({ i, i }, { i + n, i + n }, { i + n + 1, i + n + 1 }, 1)
    end
  end
  return table.concat({
    '<?xml version="1.0" encoding="utf-8"?>',
    '<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">',
    '<asset><unit name="meter" meter="1"/><up_axis>Z_UP</up_axis></asset>',
    '<library_effects><effect id="fx"><profile_COMMON><technique sid="common"><phong><diffuse><color>1 1 1 1</color></diffuse></phong></technique></profile_COMMON></effect></library_effects>',
    '<library_materials><material id="' .. material .. '" name="' .. material .. '"><instance_effect url="#fx"/></material></library_materials>',
    '<library_geometries><geometry id="mesh" name="mesh"><mesh>',
    string.format('<source id="pos"><float_array id="pos-array" count="%d">%s</float_array><technique_common><accessor source="#pos-array" count="%d" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>', #pos * 3, table.concat(pos, ' '), #pos),
    '<source id="nrm"><float_array id="nrm-array" count="6">0 0 1 0 0 -1</float_array><technique_common><accessor source="#nrm-array" count="2" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>',
    string.format('<source id="uv"><float_array id="uv-array" count="%d">%s</float_array><technique_common><accessor source="#uv-array" count="%d" stride="2"><param name="S" type="float"/><param name="T" type="float"/></accessor></technique_common></source>', #uv * 2, table.concat(uv, ' '), #uv),
    '<vertices id="vtx"><input semantic="POSITION" source="#pos"/></vertices>',
    string.format('<triangles material="%s" count="%d"><input semantic="VERTEX" source="#vtx" offset="0"/><input semantic="NORMAL" source="#nrm" offset="1"/><input semantic="TEXCOORD" source="#uv" offset="2" set="0"/>', material, count),
    '<p>' .. table.concat(tris, ' ') .. '</p></triangles>',
    '</mesh></geometry></library_geometries>',
    '<library_visual_scenes><visual_scene id="Scene" name="Scene"><node id="slpuddle" name="slpuddle" type="NODE"><instance_geometry url="#mesh" name="slpuddle"><bind_material><technique_common><instance_material symbol="' .. material .. '" target="#' .. material .. '"/></technique_common></bind_material></instance_geometry></node></visual_scene></library_visual_scenes>',
    '<scene><instance_visual_scene url="#Scene"/></scene></COLLADA>',
  }, '\n')
end
M.gridDae = gridDae          -- (for the offline test)

local function flatPath()
  local path = SHAPES .. 'puddle_flat_v3.dae'
  if not FS:fileExists(path) then writeFile(path, gridDae(nil)) end
  return path
end

-- a ripple: one small flat quad whose texture coordinates show the first frame of the ring sheet (the material plays the other seven)
local function ripplePath()
  local path = SHAPES .. 'ripple_v1.dae'
  if not FS:fileExists(path) then writeFile(path, gridDae(nil, { n = 2, material = RIPPLE_MATERIAL, uMax = 0.125 })) end
  return path
end

-- the ground heights under the grid of a puddle (world corners from its size and direction), relative to its centre height; nil entries are level
local function heightsFor(p)
  local h, n = {}, GRID
  for iy = 0, n - 1 do
    for ix = 0, n - 1 do
      local lx, ly = -0.5 + ix / (n - 1), -0.5 + iy / (n - 1)
      local wx = p.x + lx * p.sx * p.dy + ly * p.sy * p.dx
      local wy = p.y - lx * p.sx * p.dx + ly * p.sy * p.dy
      local z = groundZ(wx, wy, p.z + 2)
      h[iy * n + ix + 1] = z and math.max(-0.3, math.min(0.3, z - p.z)) or 0
    end
  end
  return h
end

local function newObject(name, path)
  if FS:fileExists(MATERIALS) and not (scenetree.findObject(MATERIAL) and scenetree.findObject(RIPPLE_MATERIAL)) then loadJsonMaterialsFile(MATERIALS) end
  local o = createObject('TSStatic')
  o:setField('shapeName', 0, path)
  o:setField('collisionType', 0, 'None')
  o:setField('decalType', 0, 'None')
  o.canSave = false
  o:registerObject(name)
  return o
end

local function deleteObject(o) if o then pcall(function() o:delete() end) end end

local function dropRipples(p)
  for _, r in ipairs(p.ripples or {}) do deleteObject(r.obj) end
  p.ripples = nil
end

local function dropPuddle(p)
  dropRipples(p)
  deleteObject(p.obj)
  p.obj = nil
  if p.file then pcall(function() FS:removeFile(p.file) end) p.file = nil end
end

local function makeObject(p)
  counter = counter + 1
  p.id = p.id or counter
  local path
  if M.flags.warp then
    path = SHAPES .. 'puddle_g' .. p.id .. '.dae'
    writeFile(path, gridDae(heightsFor(p)))
    p.file = path
  else
    path = flatPath()
  end
  return newObject('sl_pd_' .. p.id, path)
end

-- a puddle's plane put on the road: 5 cm above the centre's surface, turned to its direction, scaled by k
local function putMesh(p, k)
  local mx = MatrixF(true)
  mx:createOrientFromDirUp(vec3(p.dx, p.dy, 0), vec3(0, 0, 1))
  mx:setPosition(vec3(p.x, p.y, p.z + 0.05))
  p.obj:setTransform(mx)
  p.obj:setScale(vec3(p.sx * k, p.sy * k, 1))
  p.k = k
end

local function worldBox(o)
  local ok, box = pcall(function() return o:getWorldBox() end)
  if not ok or not box then return 'no world box' end
  local text = tostring(box)
  pcall(function() text = string.format('min %s max %s', tostring(box.minExtents), tostring(box.maxExtents)) end)
  return text
end

----------------------------------------------------------------------------------------------
-- placing and keeping puddles

local function playerPos()
  local v = getPlayerVehicle(0)
  if not v then return nil end
  local ok, pos = pcall(function() return v:getPosition() end)
  return ok and pos or nil, v
end

local function updatePlacement(dt, wet)
  local pos, v = playerPos()
  if not pos then return end
  local want = rules.puddleCount(wet)
  for i = #puddles, 1, -1 do
    local p = puddles[i]
    local dx, dy = p.x - pos.x, p.y - pos.y
    if dx * dx + dy * dy > FORGET_AT * FORGET_AT or i > want then dropPuddle(p) table.remove(puddles, i) end
  end
  placeTimer = placeTimer + dt
  if placeTimer < 0.3 or #puddles >= want then return end
  placeTimer = 0
  local heading = 0
  pcall(function() local d = v:getDirectionVector() heading = math.atan2(d.y, d.x) end)
  for _ = 1, 3 do
    local a = heading + (math.random() - 0.5) * (math.random() < 0.6 and 2.2 or 6.28)
    local r = PUDDLE_RADIUS[1] + math.random() * (PUDDLE_RADIUS[2] - PUDDLE_RADIUS[1])
    local x, y = pos.x + math.cos(a) * r, pos.y + math.sin(a) * r
    local z = roadSpot(x, y, pos.z + 12)
    if z then
      local rot = math.random() * 6.28
      -- every third one is a big faint damp patch (the road looks wet round the puddles: there is no wet material to reach); the others are puddles 2-4 m across
      local damp = stats.placed % 3 == 2
      local size = damp and (7 + math.random() * 5) or (2 + math.random() * 2)
      puddles[#puddles + 1] = { x = x, y = y, z = z, sx = size, sy = size * (0.6 + math.random() * 0.5), dx = math.cos(rot), dy = math.sin(rot), born = os.clock(), damp = damp }
      stats.placed = stats.placed + 1
      log('I', TAG, string.format('puddle placed at %.0f, %.0f, %.2f (%d of %d, wet %.2f)', x, y, z, #puddles, want, wet))
      break
    end
  end
end

-- the planes: made when a puddle is first visible (its grid is dropped onto the surface then), grown while it is new, shrunk as the road dries
local function updateMeshes(wet, intensity)
  for _, p in ipairs(puddles) do
    local f = rules.puddleAlpha(wet, os.clock() - p.born) / 0.8
    if f < 0.03 then
      if p.obj then dropPuddle(p) end
    else
      local k = 0.6 + 0.4 * f
      if p.damp and M.flags.shimmer then k = k * rules.shimmer(os.clock(), p.id or 1, intensity) end      -- (the damp patches breathe with the rain: darker, then lighter)
      if not p.obj then
        p.obj = makeObject(p)
        putMesh(p, k)
        stats.shown = stats.shown + 1
        once('first', string.format('puddle plane: first one at %.0f, %.0f, %.2f (%.1f x %.1f m, warped %s, world box %s)', p.x, p.y, p.z + 0.05, p.sx * k, p.sy * k, tostring(M.flags.warp), worldBox(p.obj)))
      elseif math.abs((p.k or 0) - k) > 0.02 then
        putMesh(p, k)
      end
    end
  end
end

-- ripples (the rain landing in the puddles): each puddle near the player has 0-3 small ring planes at random spots on it, played by the material itself; each is
-- moved to a new spot every few seconds; none while it does not rain
local function placeRipple(p, r)
  local k = p.k or 1
  local a, d = math.random() * 6.283, math.sqrt(math.random()) * 0.55
  local lx, ly = math.cos(a) * d * p.sx * k * 0.5, math.sin(a) * d * p.sy * k * 0.5
  local wx, wy = p.x + lx * p.dy + ly * p.dx, p.y - lx * p.dx + ly * p.dy
  local z = groundZ(wx, wy, p.z + 2) or p.z
  local size = 0.5 + math.random() * 0.5
  local mx = MatrixF(true)
  mx:createOrientFromDirUp(vec3(math.cos(a), math.sin(a), 0), vec3(0, 0, 1))
  mx:setPosition(vec3(wx, wy, z + 0.07))
  r.obj:setTransform(mx)
  r.obj:setScale(vec3(size, size, 1))
  r.born, r.life = os.clock(), 2.5 + math.random() * 3
end

local function updateRipples(intensity)
  local want = M.flags.ripples and rules.rippleCount(intensity) or 0
  local pos = playerPos()
  local used, now = 0, os.clock()
  for _, p in ipairs(puddles) do
    local near = pos and p.obj and not p.damp and used < 8 and (p.x - pos.x) ^ 2 + (p.y - pos.y) ^ 2 < 35 * 35
    local count = near and want or 0
    if near and count > 0 then used = used + 1 end
    p.ripples = p.ripples or {}
    while #p.ripples > count do deleteObject(p.ripples[#p.ripples].obj) table.remove(p.ripples) end
    while #p.ripples < count do
      local r = { obj = newObject('sl_pd_ripple_' .. (counter + 1), ripplePath()) }
      counter = counter + 1
      placeRipple(p, r)
      p.ripples[#p.ripples + 1] = r
      stats.ripples = stats.ripples + 1
      once('ripple', string.format('first ripple on a puddle at %.0f, %.0f (material %s %s)', p.x, p.y, RIPPLE_MATERIAL, tostring(scenetree.findObject(RIPPLE_MATERIAL) ~= nil)))
    end
    for _, r in ipairs(p.ripples) do if now - r.born > r.life then placeRipple(p, r) end end
  end
end

----------------------------------------------------------------------------------------------
-- the car: puddles near it go to its own Lua; it answers with where its wheels throw spray

local function feedVehicle(dt, wet)
  feedTimer = feedTimer + dt
  if feedTimer < 0.3 then return end
  feedTimer = 0
  local pos, v = playerPos()
  if not pos or v:getJBeamFilename() == 'unicycle' then return end
  local list = {}
  local candidates = {}
  for _, p in ipairs(puddles) do candidates[#candidates + 1] = p end
  if debugPuddle and debugPuddle.obj then candidates[#candidates + 1] = debugPuddle end      -- (the test puddle counts like a real one)
  for _, p in ipairs(candidates) do
    if p.obj and not p.damp and #list < 8 then
      local dx, dy = p.x - pos.x, p.y - pos.y
      if dx * dx + dy * dy < 45 * 45 then
        list[#list + 1] = string.format('{x=%.2f,y=%.2f,sx=%.2f,sy=%.2f,dx=%.3f,dy=%.3f,k=%.2f}', p.x, p.y, p.sx, p.sy, p.dx, p.dy, p.k or 1)
      end
    end
  end
  if #list == 0 and wet < 0.3 then
    if sentEmpty then return end
    sentEmpty = true
  else
    sentEmpty = false
  end
  v:queueLuaCommand(string.format('if slCar and slCar.setPuddles then slCar.setPuddles({%s}, %.2f, {physics=%s,splash=%s,mist=%s}) end',
    table.concat(list, ','), wet, tostring(M.flags.physics), tostring(M.flags.splash), tostring(M.flags.mist)))
end

local function emitter(i)
  local e = emitters[i]
  if e then return e end
  local o = createObject('ParticleEmitterNode')
  o:setPosition(vec3(0, 0, -500))
  o.scale = vec3(1, 1, 1)
  o:setField('rotation', 0, '1 0 0 0')
  o:setField('emitter', 0, EMITTER)
  o:setField('dataBlock', 0, 'lightExampleEmitterNodeData1')
  o.canSave = false
  o:registerObject('sl_pd_emitter_' .. i)
  pcall(function() scenetree.MissionGroup:addObject(o) end)
  e = { obj = o, on = false }
  emitters[i] = e
  once('emitter', 'water emitter ' .. EMITTER .. ' created: ' .. tostring(o ~= nil))
  return e
end

local function emitterSet(e, on, x, y, z)
  if on then pcall(function() e.obj:setPosition(vec3(x, y, z)) end) end
  if on ~= e.on then
    e.on = on
    pcall(function() e.obj.hidden = not on end)
    pcall(function() e.obj:setField('active', 0, on and 'true' or 'false') end)
    if not on then pcall(function() e.obj:setPosition(vec3(0, 0, -500)) end) end
  end
end

local function addTrail(i, x, y, z, dx, dy)
  local last = lastTrail[i]
  if last and (last[1] - x) ^ 2 + (last[2] - y) ^ 2 < 0.7 * 0.7 then return end
  lastTrail[i] = { x, y }
  if #trails >= MAX_TRAILS then deleteObject(trails[1].obj) table.remove(trails, 1) end
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 0.1 then return end
  local t = { born = os.clock(), dx = dx / len, dy = dy / len }
  t.obj = newObject('sl_pd_trail_' .. (counter + 1), flatPath())
  counter = counter + 1
  local mx = MatrixF(true)
  mx:createOrientFromDirUp(vec3(t.dx, t.dy, 0), vec3(0, 0, 1))
  mx:setPosition(vec3(x, y, z + 0.06))
  t.obj:setTransform(mx)
  t.obj:setScale(vec3(0.4, 1.1, 1))
  t.x, t.y, t.z = x, y, z
  trails[#trails + 1] = t
  stats.trails = stats.trails + 1
  once('trail', string.format('first wet trail at %.1f, %.1f', x, y))
end

local function updateTrails(dt)
  trailTimer = trailTimer + dt
  if trailTimer < 0.25 then return end
  trailTimer = 0
  local now = os.clock()
  for i = #trails, 1, -1 do
    local t = trails[i]
    local k = 1 - (now - t.born) / TRAIL_LIFE
    if k <= 0.05 then deleteObject(t.obj) table.remove(trails, i)
    else pcall(function() t.obj:setScale(vec3(0.4 * k + 0.05, 1.1 * (0.5 + 0.5 * k), 1)) end) end
  end
end

-- called from the car's Lua about ten times a second while a wheel throws anything: list = { { x, y, z, splash, mist }, ... } (ground under each wheel, a little behind it)
-- the car's Lua says a wheel is in a puddle (at most every two seconds): counted, and logged the first time
function M.wheelIn(vid, wheel, depth, speedKmh)
  stats.wheelsIn = (stats.wheelsIn or 0) + 1
  once('wheelIn', string.format('wheel in puddle: wheel %s depth %.2f speed %.0f km/h', tostring(wheel), depth or 0, speedKmh or 0))
end

function M.wheelFx(vid, list, dx, dy)
  local pv = getPlayerVehicle(0)
  if not pv or pv:getID() ~= vid then return end
  stats.fxCalls = stats.fxCalls + 1
  once('fx', string.format('wheel effects reach the game side: %d wheels, first {%s}', #(list or {}), table.concat(list and list[1] or {}, ',')))
  for i = 1, 4 do
    local w = list and list[i]
    local e = emitter(i)
    if w then
      local splash, mist = w[4] or 0, w[5] or 0
      local on = math.random() < math.max(splash, mist * 0.5)
      if on then if splash >= mist * 0.5 then stats.splashOn = stats.splashOn + 1 else stats.mistOn = stats.mistOn + 1 end end
      emitterSet(e, on, w[1], w[2], w[3] + 0.05)
      if M.flags.trail and splash > 0.25 then addTrail(i, w[1], w[2], w[3], dx or 0, dy or 0) end
    else
      emitterSet(e, false)
    end
  end
end

----------------------------------------------------------------------------------------------

function M.update(dt, wet, intensity)
  dt = dt or 0
  intensity = intensity or 0
  updatePlacement(dt, wet)
  meshTimer = meshTimer + dt
  if meshTimer > 0.25 then
    meshTimer = 0
    local ok, err = pcall(updateMeshes, wet, intensity)
    if not ok then once('meshErr', 'puddle planes: ' .. tostring(err)) end
    ok, err = pcall(updateRipples, intensity)
    if not ok then once('rippleErr', 'ripples: ' .. tostring(err)) end
  end
  feedVehicle(dt, wet)
  updateTrails(dt)
  if wet >= 0.15 and os.clock() - lastStatsLog > 15 then
    lastStatsLog = os.clock()
    log('I', TAG, string.format('puddles: %d standing, %d shown (wet %.2f); tries %d, no surface %d, not flat %d, no road %d, placed %d; wheel calls %d (splash %d, mist %d), wheels in puddles %d, trails %d, ripples made %d',
      #puddles, stats.shown, wet, stats.tries, stats.noSurface, stats.notFlat, stats.noRoad, stats.placed, stats.fxCalls, stats.splashOn, stats.mistOn, stats.wheelsIn, stats.trails, stats.ripples))
  end
end

function M.flag(name, on)
  if M.flags[name] ~= nil and on ~= nil then M.flags[name] = on == true end
  return M.flags
end

function M.stats() return stats, #puddles, #trails end

-- for a game test: one 4 m puddle 6 m in front of the player's car at once (warped to the surface like the real ones); returns where it is and the box it covers
function M.puddleNear()
  local pos, v = playerPos()
  if not pos then return 'no player vehicle' end
  local dir = v:getDirectionVector()
  local len = math.max(0.1, math.sqrt(dir.x * dir.x + dir.y * dir.y))
  local x, y = pos.x + dir.x * 6, pos.y + dir.y * 6
  local z = groundZ(x, y, pos.z + 12) or pos.z
  if debugPuddle then dropPuddle(debugPuddle) end
  debugPuddle = { x = x, y = y, z = z, sx = 4, sy = 4, dx = dir.x / len, dy = dir.y / len, k = 1 }
  debugPuddle.obj = makeObject(debugPuddle)
  putMesh(debugPuddle, 1)
  local box = worldBox(debugPuddle.obj)
  log('I', TAG, string.format('puddleNear: a 4 m puddle at %.1f, %.1f, %.2f (the road under it %.2f, the car at %.2f); warped %s; world box %s', x, y, z + 0.05, z, pos.z, tostring(M.flags.warp), box))
  return { x = x, y = y, z = z + 0.05 }, box
end

function M.clear()
  for _, p in ipairs(puddles) do dropPuddle(p) end
  puddles = {}
  if debugPuddle then dropPuddle(debugPuddle) debugPuddle = nil end
  for _, t in ipairs(trails) do deleteObject(t.obj) end
  trails, lastTrail = {}, {}
  for _, e in ipairs(emitters) do deleteObject(e.obj) end
  emitters = {}
  local pos, v = playerPos()
  if v and v:getJBeamFilename() ~= 'unicycle' then v:queueLuaCommand('if slCar and slCar.setPuddles then slCar.setPuddles({}, 0, {}) end') end
  sentEmpty = true
  logged = {}
end

function M.onStreetLegalStopped() M.clear() end
function M.onClientEndMission() M.clear() end

return M
