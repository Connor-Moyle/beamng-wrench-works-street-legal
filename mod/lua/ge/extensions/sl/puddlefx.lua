-- Street Legal: puddles and what the wheels do in them (extension name: sl_puddlefx; part of the weather, #45).
-- While the roads are wet (sl_weather's wetness) thin planes of translucent water stand on flat road spots round the player: each plane is a small grid whose
-- corners are dropped onto the surface (a ray per corner), so it follows the slope, the camber and the dips like a decal. They fade in as the rain lasts and
-- shrink as the road dries; only the ones near the player exist, the rest are deleted behind him. The car's own Lua (vehicle extension slPuddles, loaded into the player's car whatever car it is) is told which
-- puddles are near; a wheel inside one gets drag and, fast enough, aquaplanes (sl_puddles has the rules), and asks back for spray (a particle emitter at the
-- wheel, the game's own water-wheels one), the fine mist of a wet road, and a short-lived darker wet trail. Each part is behind a flag (M.flags / M.flag).

local M = {}

local rules = require('sl/core/weather')
local pr = require('sl_puddles')

local TAG = 'sl_puddlefx'
M.flags = { proc = true, warp = true, splash = true, mist = true, physics = true, trail = true, ripples = true, shimmer = true }

local MATERIALS = '/art/street_legal/main.materials.json'
local MATERIAL = 'sl_puddle'          -- translucent, alpha from its opacity map (the soft oval), shiny and dark
local RIPPLE_MATERIAL = 'sl_ripple_s' -- one crisp ring; the ripple planes grow it from small to large over about a second (the scale is moved from Lua ten times a second)
local SHAPES = '/temp/street_legal/shapes/'
local GRID = 5                        -- corners across a puddle's grid
local PUDDLE_RADIUS = { 25, 230 }      -- puddles stand between these distances from the player (far out: they grow as he comes up to them, see FADE_*)
local FORGET_AT = 270                 -- ... and are deleted beyond this
M.REFILL_FROM = 140                  -- a puddle placed while the shower is under way stands at least this far from the player
M.FADE_FROM, M.FADE_TO = 165, 225     -- a puddle is full size up to FADE_FROM metres and nothing at FADE_TO
local EMITTER = 'BNGP_50'             -- the game's own water-on-wheels emitter (the splash a wheel throws in a lake)
local MAX_TRAILS, TRAIL_LIFE = 12, 5

local puddles = {}                    -- { x, y, z, sx, sy, dx, dy, born, damp, id, obj, k }
local trails = {}                     -- { obj, born, dx, dy }
local lastTrail = {}                  -- the last trail put down per wheel index: { x, y }
local emitters = {}                   -- the four particle emitters, reused
local counter = 0
local placeTimer, meshTimer, feedTimer, trailTimer, rippleTimer = 0, 0, 0, 0, 0
local debugPuddle
local sentEmpty = true
local stats = { tries = 0, noSurface = 0, notFlat = 0, noRoad = 0, placed = 0, shown = 0, fxCalls = 0, splashOn = 0, mistOn = 0, trails = 0, wheelsIn = 0, ripples = 0, rejected = 0 }
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
  return z, n1, radius
end

-- a flat spot on bare or hard ground near a road (a verge, a car park, a shoulder): the terrain layer under it is asphalt, concrete, dirt, gravel or rock, never grass
local groundOk = {}                   -- terrain layer index -> true | false
local function groundSpot(x, y, zTop)
  stats.tries = stats.tries + 1
  local z = groundZ(x, y, zTop)
  if not z then stats.noSurface = stats.noSurface + 1 return nil end
  for _, d in ipairs({ { 1.4, 0 }, { -1.4, 0 }, { 0, 1.4 }, { 0, -1.4 } }) do
    local zz = groundZ(x + d[1], y + d[2], zTop)
    if not zz or math.abs(zz - z) > 0.25 then stats.notFlat = stats.notFlat + 1 return nil end
  end
  local t = core_terrain and core_terrain.getTerrain and core_terrain.getTerrain()
  if not t then return nil end
  local ok, idx = pcall(function() return t:getMaterialIdxWs(vec3(x, y, z)) end)
  if not ok or idx == nil then return nil end
  if groundOk[idx] == nil then
    local okN, name = pcall(function() return t:getMaterialName(idx) end)
    groundOk[idx] = okN and rules.dampGroundOk(name) or false
    log('I', TAG, string.format('terrain layer %s (%s) takes damp patches: %s', tostring(idx), tostring(okN and name or '?'), tostring(groundOk[idx])))
  end
  if not groundOk[idx] then stats.badGround = (stats.badGround or 0) + 1 return nil end
  local okR, n1 = pcall(function() return map.findClosestRoad(vec3(x, y, z), 45) end)
  if not (okR and n1) then stats.noRoad = stats.noRoad + 1 return nil end
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
  local path = SHAPES .. 'ripple_v2.dae'
  if not FS:fileExists(path) then writeFile(path, gridDae(nil, { n = 2, material = RIPPLE_MATERIAL })) end
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

-- how a puddle's ground is: the range of the grid's heights and the biggest step between neighbouring corners (a kerb or a block edge is a step; a crown is a slope)
local function groundShape(h)
  local n, lo, hi, step = GRID, math.huge, -math.huge, 0
  for iy = 0, n - 1 do
    for ix = 0, n - 1 do
      local v = h[iy * n + ix + 1]
      lo, hi = math.min(lo, v), math.max(hi, v)
      if ix < n - 1 then step = math.max(step, math.abs(v - h[iy * n + ix + 2])) end
      if iy < n - 1 then step = math.max(step, math.abs(v - h[(iy + 1) * n + ix + 1])) end
    end
  end
  return hi - lo, step
end
M.groundShape = groundShape          -- (for the offline test)
M.MAX_RANGE, M.MAX_STEP = 0.15, 0.04      -- more than this and the spot is not a puddle's (a kerb, a block, a dip)

local function newObject(name, path)
  if FS:fileExists(MATERIALS) and not (scenetree.findObject(MATERIAL) and scenetree.findObject(RIPPLE_MATERIAL) and scenetree.findObject('sl_puddle_deep') and scenetree.findObject('sl_puddle_thin')) then loadJsonMaterialsFile(MATERIALS) end
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

-- A puddle's plane built in memory: a ProceduralMesh (the engine object the game's own road and planet tools use) made from the grid heights, in world axes round the puddle's centre
-- with its size and direction baked in, one skin (the material is double sided). No file is written; the object is moved and scaled (to grow) like any other. Returns nil when the
-- engine refuses (the caller then falls back to a file). The mesh table: verts, uvs, normals, faces (0-based v, u, n), material.
local function procPuddle(name, p, h)
  if FS:fileExists(MATERIALS) and not (scenetree.findObject(MATERIAL) and scenetree.findObject('sl_puddle_deep') and scenetree.findObject('sl_puddle_thin')) then loadJsonMaterialsFile(MATERIALS) end
  local n = GRID
  local verts, uvs, faces = {}, {}, {}
  for iy = 0, n - 1 do
    for ix = 0, n - 1 do
      local lx, ly = -0.5 + ix / (n - 1), -0.5 + iy / (n - 1)
      verts[#verts + 1] = { x = lx * p.sx * p.dy + ly * p.sy * p.dx, y = -lx * p.sx * p.dx + ly * p.sy * p.dy, z = h[iy * n + ix + 1] or 0 }
      uvs[#uvs + 1] = { u = ix / (n - 1), v = iy / (n - 1) }
    end
  end
  for iy = 0, n - 2 do
    for ix = 0, n - 2 do
      local i = iy * n + ix
      for _, c in ipairs({ i, i + 1, i + n + 1, i, i + n + 1, i + n }) do faces[#faces + 1] = { v = c, u = c, n = 0 } end
    end
  end
  local ok, o = pcall(function()
    local proc = createObject('ProceduralMesh')
    proc:registerObject(name)
    proc.canSave = false
    pcall(function() scenetree.MissionGroup:addObject(proc) end)
    proc:createMesh({ { { verts = verts, uvs = uvs, normals = { { x = 0, y = 0, z = 1 } }, faces = faces, material = p.material or MATERIAL } } })
    return proc
  end)
  if ok and o then return o end
  once('procFail', 'a puddle plane could not be made in memory (' .. tostring(o) .. '): falling back to files')
  return nil
end

local function makeObject(p, force)
  counter = counter + 1
  p.id = p.id or counter
  local path
  if M.flags.warp then
    local h = heightsFor(p)
    local range, step = groundShape(h)
    -- a damp patch is big and faint: it may cross a crown; a puddle must lie on one even surface (no kerb, no step)
    if not force and (step > M.MAX_STEP * (p.damp and 2 or 1) or range > M.MAX_RANGE * (p.damp and 2 or 1)) then
      stats.rejected = stats.rejected + 1
      once('reject', string.format('a puddle spot was rejected: ground range %.1f cm, biggest step %.1f cm (limits %.0f / %.0f)', range * 100, step * 100, M.MAX_RANGE * 100, M.MAX_STEP * 100))
      return nil
    end
    p.range, p.step = range, step
    if M.flags.proc then
      local o = procPuddle('sl_pd_' .. p.id, p, h)
      if o then p.proc = true return o end
      M.flags.proc = false      -- (the engine does not take it: files from now on)
    end
    path = SHAPES .. 'puddle_g' .. p.id .. '.dae'
    writeFile(path, gridDae(h, { material = p.material }))
    p.file = path
  else
    path = flatPath()
  end
  return newObject('sl_pd_' .. p.id, path)
end

-- a puddle's plane put on the road: 5 cm above the centre's surface, turned to its direction, scaled by k
local function putMesh(p, k)
  if p.proc then
    -- the mesh has its size and direction in its vertices: only its place and the growing scale
    pcall(function() p.obj:setPosition(vec3(p.x, p.y, p.z + 0.05)) end)
    local ok = pcall(function() p.obj:setScale(vec3(k, k, 1)) end)
    if not ok then pcall(function() p.obj.scale = vec3(k, k, 1) end) end
    p.k = k
    return
  end
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
  local budget = sl_options and sl_options.get and sl_options.get('slPuddleCount')
  if type(budget) == 'number' then rules.MAX_PUDDLES = budget end      -- (the setting: how many puddles stand at most)
  local want = rules.puddleCount(wet)
  for i = #puddles, 1, -1 do
    local p = puddles[i]
    local dx, dy = p.x - pos.x, p.y - pos.y
    if dx * dx + dy * dy > FORGET_AT * FORGET_AT or i > want then dropPuddle(p) table.remove(puddles, i) end
  end
  placeTimer = placeTimer + dt
  -- (a car at speed leaves puddles behind faster than one try in four per 0.15 s makes new ones ahead: far short of the setting; catch up faster while well under it)
  local behind = #puddles < want * 0.8
  if placeTimer < (behind and 0.06 or 0.15) or #puddles >= want then return end
  placeTimer = 0
  local heading = 0
  pcall(function() local d = v:getDirectionVector() heading = math.atan2(d.y, d.x) end)
  local t0 = os.clock()
  for _ = 1, (behind and 8 or 4) do
    if os.clock() - t0 > 0.002 then break end      -- (catching up never costs more than ~2 ms of a frame)
    local a = heading + (math.random() - 0.5) * (math.random() < 0.6 and 2.2 or 6.28)
    -- (the first puddles of a shower may stand near: they fade in with the rain's age; later ones are only placed beyond sight, so none appears in view)
    local minR = #puddles < want * 0.4 and PUDDLE_RADIUS[1] or M.REFILL_FROM
    local r = minR + math.sqrt(math.random()) * (PUDDLE_RADIUS[2] - minR)      -- (the square root: more of them out where there is more ground)
    local x, y = pos.x + math.cos(a) * r, pos.y + math.sin(a) * r
    -- every fourth try is for bare ground beside the road (verges, car parks): a damp patch there, so the ground is not dry next to wet asphalt
    local ground = stats.placed % 4 == 3
    local z, node, half
    if ground then z = groundSpot(x, y, pos.z + 12) else z, node, half = roadSpot(x, y, pos.z + 12) end
    if z then
      local pool = ground and { kind = 'ground', sx = 7 + math.random() * 6, damp = true, material = 'sl_puddle' } or rules.pool(math.random)
      if ground then pool.sy = pool.sx * (0.6 + math.random() * 0.5) end
      local rot = math.random() * 6.28
      local px, py = x, y
      if node and (pool.lateral or 0) > 0 then
        -- along the road and off its middle: toward an edge, a wheel track, a gutter. The direction is that of the road node's first link.
        local nodes = map.getMap().nodes
        local n = nodes[node]
        local dirx, diry
        for nb in pairs(n.links or {}) do
          local q = nodes[nb]
          if q and q.pos then
            local ddx, ddy = q.pos.x - n.pos.x, q.pos.y - n.pos.y
            local len = math.sqrt(ddx * ddx + ddy * ddy)
            if len > 2 then dirx, diry = ddx / len, ddy / len break end
          end
        end
        if dirx then
          local side = math.random() < 0.5 and 1 or -1
          local off = side * pool.lateral * (half or 3)
          px, py = n.pos.x - diry * off, n.pos.y + dirx * off
          if pool.along then rot = math.atan2(diry, dirx) end
          local z2 = groundZ(px, py, pos.z + 12)
          if not z2 or math.abs(z2 - z) > 0.2 then z = nil else z = z2 end
        elseif pool.along then z = nil end      -- (a long pool with no road direction to lie along)
      elseif pool.along then z = nil end
      -- a dip: the ground in the middle is lower than 3 m round it (water would stand there)
      if z and pool.dip then
        local lower = 0
        for _, d in ipairs({ { 3, 0 }, { -3, 0 }, { 0, 3 }, { 0, -3 } }) do
          local zz = groundZ(px + d[1], py + d[2], pos.z + 12)
          if zz and zz - z > 0.012 then lower = lower + 1 end
        end
        if lower < 2 then z = nil stats.noDip = (stats.noDip or 0) + 1 end
      end
      if z then
        puddles[#puddles + 1] = { x = px, y = py, z = z, sx = pool.sx, sy = pool.sy, dx = math.cos(rot), dy = math.sin(rot), born = os.clock(), damp = pool.damp, kind = pool.kind, material = pool.material }
        stats.placed = stats.placed + 1
        stats.kinds = stats.kinds or {}
        stats.kinds[pool.kind] = (stats.kinds[pool.kind] or 0) + 1
        log('I', TAG, string.format('%s puddle placed at %.0f, %.0f, %.2f (%d of %d, wet %.2f)', pool.kind, px, py, z, #puddles, want, wet))
        break
      end
    end
  end
end

-- the planes: made when a puddle is first visible (its grid is dropped onto the surface then), grown while it is new, shrunk as the road dries
local function updateMeshes(wet, intensity)
  local pos = playerPos()
  local made = 0                                  -- (two planes are built per pass, four passes a second: each is 25 rays and a file; their time is measured)
  for _, p in ipairs(puddles) do
    local f = rules.puddleAlpha(wet, os.clock() - p.born) / 0.8
    -- size: it grows while it is new (from 15 %) and with the wetness, and with the distance: out at the edge of the view it is nothing, so it never pops in
    local g = pos and rules.distanceScale(math.sqrt((p.x - pos.x) ^ 2 + (p.y - pos.y) ^ 2), M.FADE_FROM, M.FADE_TO) or 1
    local size = f < 0.03 and 0 or (0.15 + 0.85 * f) * g
    if size < 0.04 then
      if p.obj and (f < 0.03 or g < 0.03) then dropPuddle(p) end
    elseif not p.obj and not p.dead and made >= 2 then
      -- (next pass)
    else
      local k = size
      if p.damp and M.flags.shimmer then k = k * rules.shimmer(os.clock(), p.id or 1, intensity) end      -- (the damp patches breathe with the rain: darker, then lighter)
      if not p.obj and not p.dead then
        made = made + 1
        local t0 = os.clock()
        p.obj = makeObject(p)
        stats.makes, stats.makeMs = (stats.makes or 0) + 1, (stats.makeMs or 0) + (os.clock() - t0) * 1000
        if not p.obj then p.dead = true end
        if p.obj then putMesh(p, k) stats.shown = stats.shown + 1 end
        if p.obj and stats.shown == 1 then
        once('first', string.format('puddle plane: first one at %.0f, %.0f, %.2f (%.1f x %.1f m, warped %s, ground range %.1f cm, step %.1f cm, world box %s)', p.x, p.y, p.z + 0.05, p.sx * k, p.sy * k, tostring(M.flags.warp), (p.range or 0) * 100, (p.step or 0) * 100, worldBox(p.obj))) end
      elseif p.obj and math.abs((p.k or 0) - k) > 0.02 then
        putMesh(p, k)
      end
    end
  end
end

local function removeDead()
  for i = #puddles, 1, -1 do
    if puddles[i].dead then dropPuddle(puddles[i]) table.remove(puddles, i) end
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
  local mx = MatrixF(true)
  mx:createOrientFromDirUp(vec3(math.cos(a), math.sin(a), 0), vec3(0, 0, 1))
  mx:setPosition(vec3(wx, wy, z + 0.08))
  r.obj:setTransform(mx)
  r.size, r.born, r.life = 0.35 + math.random() * 0.45, os.clock() - math.random() * 0.8, 0.9 + math.random() * 0.6   -- (rings of 0.35-0.8 m across when full, faint (ripple.color is a grey-blue, its opacity a quarter of what it was), each at its own point of growing)
  r.obj:setScale(vec3(0.05, 0.05, 1))
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
  end
end

-- the rings grow (from a dot to full size over their life), ten times a second: the ripple of a drop landing in the puddle, then another one elsewhere
local function growRipples()
  local now = os.clock()
  for _, p in ipairs(puddles) do
    for _, r in ipairs(p.ripples or {}) do
      local age = now - r.born
      if age > r.life then placeRipple(p, r) age = now - r.born end
      local k = math.max(0.05, math.min(1, age / r.life))
      pcall(function() r.obj:setScale(vec3(r.size * k, r.size * k, 1)) end)
    end
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
  v:queueLuaCommand(string.format('if not slPuddles then extensions.load("slPuddles") end if slPuddles then slPuddles.setPuddles({%s}, %.2f, {physics=%s,splash=%s,mist=%s}) end',
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

-- the splash a wheel throws is smaller by the setting Splash size (1 is the game's emitter as it is): the particles leave slower, so the spray is lower, and fewer wheel passes make one
local function splashSize()
  local v = sl_options and sl_options.get and sl_options.get('slSplashSize')
  return type(v) == 'number' and v or 0.4
end
local function emitterSet(e, on, x, y, z)
  local size = splashSize()
  if e.size ~= size then
    e.size = size
    pcall(function() e.obj:setField('velocity', 0, tostring(size)) end)
  end
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
      local on = math.random() < math.max(splash, mist * 0.5) * math.min(1, splashSize() * 1.5)
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
  -- dry road, nothing standing, nothing to draw and the car already told so: no player or car calls at all (hitch recordings showed ~8 ms a frame here while cars were being built)
  if wet < 0.01 and sentEmpty and #puddles == 0 and #trails == 0 and not debugPuddle then return end
  local t0 = os.clock()
  updatePlacement(dt, wet)
  local tPlace = os.clock() - t0
  local tMesh = 0
  meshTimer = meshTimer + dt
  if meshTimer > 0.25 then
    meshTimer = 0
    local t1 = os.clock()
    local ok, err = pcall(updateMeshes, wet, intensity)
    tMesh = os.clock() - t1
    if not ok then once('meshErr', 'puddle planes: ' .. tostring(err)) end
    removeDead()
    ok, err = pcall(updateRipples, intensity)
    if not ok then once('rippleErr', 'ripples: ' .. tostring(err)) end
  end
  rippleTimer = rippleTimer + dt
  if rippleTimer > 0.1 then rippleTimer = 0 pcall(growRipples) end
  feedVehicle(dt, wet)
  updateTrails(dt)
  -- a slow pass is logged with its parts (at most one line every 2 s), so a hitch in a drive can be told from the road streaming
  local total = os.clock() - t0
  if total > 0.012 and os.clock() - (M.lastSlow or 0) > 2 then
    M.lastSlow = os.clock()
    log('W', TAG, string.format('slow puddle pass: %.0f ms (placing %.0f, planes %.0f, rest %.0f); %d standing', total * 1000, tPlace * 1000, tMesh * 1000, (total - tPlace - tMesh) * 1000, #puddles))
  end
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

-- for a game test: how the standing puddles look from the player, nearest first: { distance m, scale, built, x, y }
function M.sample()
  local pos = playerPos()
  local out = {}
  for _, p in ipairs(puddles) do
    if pos then out[#out + 1] = { math.floor(math.sqrt((p.x - pos.x) ^ 2 + (p.y - pos.y) ^ 2) + 0.5), math.floor((p.k or 0) * 100) / 100, p.obj ~= nil, math.floor(p.x), math.floor(p.y) } end
  end
  table.sort(out, function(x, y) return x[1] < y[1] end)
  return out
end

function M.stats() return stats, #puddles, #trails end
-- what the puddles cost: planes built so far, ms per plane, how many stand, the kinds placed
function M.cost()
  local kinds = {}
  for k, n in pairs(stats.kinds or {}) do kinds[#kinds + 1] = k .. ' ' .. n end
  table.sort(kinds)
  return string.format('puddles: %d standing, %d planes built (avg %.1f ms each), %d rejected, no dip %d, bad ground %d; kinds placed: %s', #puddles, stats.makes or 0,
    (stats.makes or 0) > 0 and (stats.makeMs or 0) / stats.makes or 0, stats.rejected or 0, stats.noDip or 0, stats.badGround or 0, table.concat(kinds, ', '))
end

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
  debugPuddle.obj = makeObject(debugPuddle, true)
  putMesh(debugPuddle, 1)
  local box = worldBox(debugPuddle.obj)
  log('I', TAG, string.format('puddleNear: a 4 m puddle at %.1f, %.1f, %.2f (the road under it %.2f, the car at %.2f); warped %s; ground range %.1f cm, biggest step %.1f cm (a real one is refused above %.0f / %.0f); world box %s',
    x, y, z + 0.05, z, pos.z, tostring(M.flags.warp), (debugPuddle.range or 0) * 100, (debugPuddle.step or 0) * 100, M.MAX_RANGE * 100, M.MAX_STEP * 100, box))
  return { x = x, y = y, z = z + 0.05 }, box
end

-- for a game test: one 2 m ring standing still 8 m in front of the player's car (proves the ripple material and plane draw); ringTest(false) takes it away
local ringObj
function M.ringTest(on)
  if ringObj then deleteObject(ringObj) ringObj = nil end
  if on == false then return 'removed' end
  local pos, v = playerPos()
  if not pos then return 'no player vehicle' end
  local dir = v:getDirectionVector()
  local x, y = pos.x + dir.x * 8, pos.y + dir.y * 8
  local z = groundZ(x, y, pos.z + 12) or pos.z
  ringObj = newObject('sl_pd_ringtest', ripplePath())
  local mx = MatrixF(true)
  mx:createOrientFromDirUp(vec3(dir.x, dir.y, 0), vec3(0, 0, 1))
  mx:setPosition(vec3(x, y, z + 0.08))
  ringObj:setTransform(mx)
  ringObj:setScale(vec3(2, 2, 1))
  log('I', TAG, string.format('ringTest: a 2 m ring at %.1f, %.1f, %.2f; world box %s; material %s', x, y, z + 0.08, worldBox(ringObj), tostring(scenetree.findObject(RIPPLE_MATERIAL) ~= nil)))
  return { x = x, y = y, z = z + 0.08 }
end

function M.clear()
  if ringObj then deleteObject(ringObj) ringObj = nil end
  for _, p in ipairs(puddles) do dropPuddle(p) end
  puddles = {}
  groundOk = {}                                  -- (a new level numbers its terrain layers again)
  if debugPuddle then dropPuddle(debugPuddle) debugPuddle = nil end
  for _, t in ipairs(trails) do deleteObject(t.obj) end
  trails, lastTrail = {}, {}
  for _, e in ipairs(emitters) do deleteObject(e.obj) end
  emitters = {}
  local pos, v = playerPos()
  if v and v:getJBeamFilename() ~= 'unicycle' then v:queueLuaCommand('if slPuddles then slPuddles.setPuddles({}, 0, {}) end') end
  sentEmpty = true
  logged = {}
end

function M.onStreetLegalStopped() M.clear() end
function M.onClientEndMission() M.clear() end

return M
