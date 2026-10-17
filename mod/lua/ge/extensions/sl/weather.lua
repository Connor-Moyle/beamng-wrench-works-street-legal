-- Street Legal: the weather (extension name: sl_weather; #45)
-- Each phase of each career day has a weather state (sl/core/weather): clear, cloudy, rain (light, medium or heavy), or fog banks at night. The level's own sky
-- is moved to it over a few seconds through the game's own environment calls (core_environment: cloud cover, the high cirrus cloud, fog and the number of
-- rain drops; the game no longer has a sky brightness, so a thick overcast is what darkens a rainy sky). The rain's drop count and speed follow how hard it
-- rains. The roads get wet while it rains (sl/core/weather.wetStep) and dry out afterwards: puddle decals stand on flat road spots round the player,
-- drawn each frame from a small list (nothing is kept in the world). The grip of the player's tyres follows the state (slCar.setGrip), and what jobs, purses
-- and prizes pay goes up a little in the wet (sl_career.payOut asks bonus()). The phone shows the forecast. The level's own values are put back when the
-- career stops. The career's clock and time of day are not touched (the game's own weather presets would set the time of day).

local M = {}

local rules = require('sl/core/weather')

local current, target            -- the sky now and where it is going: { drops, cloud, cirrus, density, fog, grip, wet, speed }
local baseline                   -- the level's own values, kept to put back
local stateId = 'clear'
local levelId = 'medium'
local nextId
local blendT, blendFrom = 1, nil
local BLEND_SECONDS = 25
local gripTimer, applyTimer = 0, 0
local lastKey

local wet = 0                    -- how wet the roads are, 0..1
local lastRain                   -- the rain that wet them (core/weather.resolve), for the grip it leaves
local puddles = {}               -- { x, y, z, sx, sy, dx, dy, born }
local puddleTimer = 0
local pool, poolSize, colors = {}, 0, {}
local PUDDLE_TEX = 'art/street_legal/decals/puddle.png'
local puddleMode = 'mesh'        -- 'mesh' (a thin textured plane per puddle, a stock-style translucent decal material: the dynamic decal manager drew nothing), 'decal' (the
                                 -- dynamic decal manager) or 'prism' (flat dark shapes with the debug drawer). sl_weather.puddleMode('prism') forces one for a test.
local MATERIALS = '/art/street_legal/main.materials.json'
local MATERIAL_NAMES = { map = 'sl_puddle', alpha = 'sl_puddle_a', opaque = 'sl_puddle_opaque' }      -- map: alpha from its own opacity map; alpha: from the colour map's alpha; opaque: dark grey, no maps
local puddleMaterial = 'map'
local function shapePath(kind) return '/temp/street_legal/shapes/puddle_' .. MATERIAL_NAMES[kind or puddleMaterial] .. '_v2.dae' end
local meshes = {}                -- the plane objects, reused: { obj, shown }
local PUDDLE_RADIUS = { 8, 70 }  -- puddles stand between these distances from the player; further than FORGET_AT they are dropped
local FORGET_AT = 95
local DEPTH = 1.5

local TAG = 'sl_weather'
local stats = { tries = 0, noSurface = 0, notFlat = 0, noRoad = 0, placed = 0, drawn = 0 }
local lastStatsLog = 0
local tintBase = {}              -- the sky colours the game's own gradients set, last seen; the tint pulls them to grey
local tintTimer = 0

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local function objects(className)
  local ok, list = pcall(getObjectsByClass, className)
  return ok and type(list) == 'table' and list or {}
end

local function first(className) for _, o in pairs(objects(className)) do return o end end

-- the level's rain: WCUSA has one (WCA_rain, numDrops 0); a level without one gets one made, as the editor makes it (datablock rain_drop)
local function ensureRain()
  if first('Precipitation') then return end
  local ok, err = pcall(function()
    local o = createObject('Precipitation')
    o:setField('dataBlock', 0, 'rain_drop')
    o:setField('boxWidth', 0, '50') o:setField('boxHeight', 0, '50')
    o:setField('dropSize', 0, '0.2') o:setField('splashSize', 0, '0.2')
    o:setField('minSpeed', 0, '0.35') o:setField('maxSpeed', 0, '0.4')
    o:setField('hitVehicles', 0, 'true') o:setField('useTurbulence', 0, 'true')
    o:setField('numDrops', 0, '0')
    o:registerObject('sl_weather_rain')
    local group = scenetree.findObject('MissionGroup')
    if group and group.addObject then group:addObject(o) end
  end)
  log(ok and 'I' or 'W', TAG, ok and 'the level had no Precipitation: one was made (datablock rain_drop)' or ('could not make a Precipitation: ' .. tostring(err)))
end

local function readBaseline()
  if baseline then return end
  ensureRain()
  baseline = { drops = 0, cloud = 1, fog = 0.00035, grip = 1, wet = 0 }
  local rain, cloud, info = first('Precipitation'), first('CloudLayer'), first('LevelInfo')
  if rain then
    baseline.drops = tonumber(rain.numOfDrops) or tonumber(rain.numDrops) or baseline.drops
    baseline.minSpeed, baseline.maxSpeed = tonumber(rain.minSpeed), tonumber(rain.maxSpeed)
  end
  if cloud then
    baseline.cloud = tonumber(cloud.coverage) or baseline.cloud
    baseline.cirrus, baseline.density = tonumber(cloud.cirrusCoverage), tonumber(cloud.cirrusDensity)
  end
  if info then baseline.fog = tonumber(info.fogDensity) or baseline.fog end
  baseline.speed = 1
  current = current or { drops = baseline.drops, cloud = baseline.cloud, cirrus = baseline.cirrus, density = baseline.density, fog = baseline.fog, grip = 1, wet = 0, speed = 1, tint = 0 }
  pcall(function() log('I', TAG, string.format('level sky: Precipitation %s (numOfDrops %s, numDrops %s, dataBlock %s), CloudLayer %s (coverage %s), LevelInfo fog %s, ScatterSky %s, core_environment %s, decal manager %s',
    tostring(rain ~= nil), tostring(rain and rain.numOfDrops), tostring(rain and rain.numDrops), tostring(rain and rain:getField('dataBlock', 0)), tostring(cloud ~= nil), tostring(cloud and cloud.coverage),
    tostring(info and info.fogDensity), tostring(first('ScatterSky') ~= nil), tostring(core_environment ~= nil), tostring(Engine and Engine.Render and Engine.Render.DynamicDecalMgr ~= nil))) end)
end

-- the game's own environment calls (they apply the change to the object: a plain field write on a CloudLayer or the fog is not seen until the object is
-- applied); the fields are the way back where a call is missing
local function try(fn, ...) if fn then pcall(fn, ...) end end
local function applySky(v)
  local env = core_environment
  local rain, cloud, info = first('Precipitation'), first('CloudLayer'), first('LevelInfo')
  if env and env.setCloudCover then
    try(env.setCloudCover, v.cloud)
    if v.cirrus then try(env.setCloudCirrusCoverage, v.cirrus) end
    if v.density then try(env.setCloudCirrusDensity, v.density) end
    try(env.setFogDensity, v.fog)
    try(env.setPrecipitation, math.floor(v.drops + 0.5))
  else
    if rain then pcall(function() rain.numOfDrops = math.floor(v.drops + 0.5) end) end
    if cloud then pcall(function() cloud.coverage = v.cloud if cloud.postApply then cloud:postApply() end end) end
    if info then pcall(function() info.fogDensity = v.fog if info.postApply then info:postApply() end end) end
  end
  -- how fast the drops fall follows how hard it rains (a factor on the level's own speeds)
  if rain and baseline and baseline.minSpeed and v.speed then
    pcall(function() rain.minSpeed, rain.maxSpeed = baseline.minSpeed * v.speed, baseline.maxSpeed * v.speed end)
  end
  -- fatter drops in heavier rain (they are thin streaks at the level's own 0.2)
  if rain then pcall(function() rain:setField('dropSize', 0, tostring(0.2 + math.min(1, v.drops / 3000) * 0.25)) end) end
  -- every drop count change is logged once (what the object says before and after): the rain that is not seen is found here
  local want = math.floor(v.drops + 0.5)
  if rain and want ~= M.lastLoggedDrops then
    M.lastLoggedDrops = want
    local after = tonumber(rain.numOfDrops) or tonumber(rain.numDrops)
    local hidden
    pcall(function() hidden = rain.isHidden and rain:isHidden() or rain.hidden end)
    log('I', TAG, string.format('rain drops set to %d: the object now says %s (hidden %s, enabled %s)', want, tostring(after), tostring(hidden), tostring(rain.isEnabled)))
    pcall(function() if rain.setHidden then rain:setHidden(false) end end)
  end
end

-- the sky's sun, fog and ambient colours come from gradients that follow the time of day (at dawn they are orange, and a fog in them is an orange dust storm).
-- In rain they are pulled towards grey of the same brightness; the game rewrites them with the time of day, so this is repeated twice a second while it is on.
local TINT_FIELDS = { 'sunScale', 'fogScale', 'ambientScale' }
local function applyTint(amount)
  local sky = first('ScatterSky')
  if not sky then return end
  for _, k in ipairs(TINT_FIELDS) do
    pcall(function()
      local text = sky:getField(k, 0)
      local r, g, b, a = tostring(text):match('([%-%d%.e]+)%s+([%-%d%.e]+)%s+([%-%d%.e]+)%s*([%-%d%.e]*)')
      if not r then return end
      local c = rules.greyer({ tonumber(r), tonumber(g), tonumber(b) }, amount)
      sky:setField(k, 0, string.format('%f %f %f %s', c[1], c[2], c[3], a ~= '' and a or '1'))
    end)
  end
  pcall(function() if sky.postApply then sky:postApply() end end)
end

-- the state of this phase of this day; a new one is blended in
local function sync()
  local s = career()
  if not s then return end
  readBaseline()
  local phase = sl_career.phase() or 'day'
  local key = tostring(s.day) .. ':' .. phase
  if key == lastKey then return end
  lastKey = key
  stateId = rules.forecast(s.seed, s.day, phase)
  levelId = stateId == 'rain' and rules.level(s.seed, s.day, phase) or nil
  local np, nd = rules.after(phase, s.day)
  nextId = rules.forecast(s.seed, nd, np)
  local st = rules.resolve(stateId, levelId)
  -- clear skies are the level's own fog, high cloud and speeds, and a lighter cloud cover than its default
  if st.id == 'rain' then lastRain = st end
  -- (rain's grip comes from the wetness, not from the state: a road stays slippery after the rain has stopped)
  target = { drops = st.drops, cloud = st.cloud, fog = st.id == 'clear' and baseline.fog or st.fog, grip = st.id == 'rain' and 1 or st.grip, wet = st.wet or 0, tint = st.tint or 0,
    cirrus = st.cirrus or baseline.cirrus, density = st.density or baseline.density, speed = st.speed or 1 }
  blendFrom, blendT = current, 0
  extensions.hook('onStreetLegalWeather', stateId)
end

function M.state() return stateId end
function M.level() return levelId end
function M.wetness() return wet end
function M.bonus() return career() and rules.pay(stateId) or 1 end
-- the grip factor now: fog's own, or what the wet road leaves (whichever is less)
function M.grip() return career() and math.min(current and current.grip or 1, rules.wetGrip(wet, lastRain)) or 1 end
function M.forecast()
  if not career() then return nil end
  return { state = stateId, level = levelId, name = rules.state(stateId).name, text = rules.text(sl_career.phase() or 'day', stateId, nextId, levelId), wet = stateId == 'rain' }
end

-- the car's tyres take the grip (the player's own car; a car swapped in is told at the next look)
local function pushGrip(force)
  local v = getPlayerVehicle(0)
  if not v or v:getJBeamFilename() == 'unicycle' then return end
  v:queueLuaCommand(string.format('if slCar and slCar.setGrip then slCar.setGrip(%f) end', M.grip()))
end

----------------------------------------------------------------------------------------------
-- puddles: wet road spots near the player, from a short list that is drawn each frame (DynamicDecalMgr keeps nothing)

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

local function updatePuddles(dtReal)
  local v = getPlayerVehicle(0)
  if not v then return end
  local ok, pos = pcall(function() return v:getPosition() end)
  if not ok or not pos then return end
  local want = rules.puddleCount(wet)
  -- forget the ones left behind, and the extra ones when it has dried out a little
  for i = #puddles, 1, -1 do
    local p = puddles[i]
    local dx, dy = p.x - pos.x, p.y - pos.y
    if dx * dx + dy * dy > FORGET_AT * FORGET_AT or i > want then table.remove(puddles, i) end
  end
  puddleTimer = puddleTimer + (dtReal or 0)
  if puddleTimer < 0.3 or #puddles >= want then return end
  puddleTimer = 0
  -- a few tries a round: anywhere in the ring, more often ahead of the car
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

-- the plane's model: one unit square on the ground with its texture coordinates, written once
local function planeDae(material)
  return table.concat({
    '<?xml version="1.0" encoding="utf-8"?>',
    '<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">',
    '<asset><unit name="meter" meter="1"/><up_axis>Z_UP</up_axis></asset>',
    '<library_effects><effect id="fx"><profile_COMMON><technique sid="common"><phong><diffuse><color>1 1 1 1</color></diffuse></phong></technique></profile_COMMON></effect></library_effects>',
    '<library_materials><material id="' .. material .. '" name="' .. material .. '"><instance_effect url="#fx"/></material></library_materials>',
    '<library_geometries><geometry id="mesh" name="mesh"><mesh>',
    '<source id="pos"><float_array id="pos-array" count="24">-0.5 -0.5 0 0.5 -0.5 0 0.5 0.5 0 -0.5 0.5 0 -0.5 -0.5 0.01 0.5 -0.5 0.01 0.5 0.5 0.01 -0.5 0.5 0.01</float_array><technique_common><accessor source="#pos-array" count="8" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>',
    '<source id="nrm"><float_array id="nrm-array" count="6">0 0 1 0 0 -1</float_array><technique_common><accessor source="#nrm-array" count="2" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>',
    '<source id="uv"><float_array id="uv-array" count="8">0 0 1 0 1 1 0 1</float_array><technique_common><accessor source="#uv-array" count="4" stride="2"><param name="S" type="float"/><param name="T" type="float"/></accessor></technique_common></source>',
    '<vertices id="vtx"><input semantic="POSITION" source="#pos"/></vertices>',
    '<triangles material="' .. material .. '" count="4"><input semantic="VERTEX" source="#vtx" offset="0"/><input semantic="NORMAL" source="#nrm" offset="1"/><input semantic="TEXCOORD" source="#uv" offset="2" set="0"/>',
    '<p>4 0 0 5 0 1 6 0 2 4 0 0 6 0 2 7 0 3 0 1 0 2 1 2 1 1 1 0 1 0 3 1 3 2 1 2</p></triangles>',
    '</mesh></geometry></library_geometries>',
    '<library_visual_scenes><visual_scene id="Scene" name="Scene"><node id="slpuddle" name="slpuddle" type="NODE"><instance_geometry url="#mesh" name="slpuddle"><bind_material><technique_common><instance_material symbol="' .. material .. '" target="#' .. material .. '"/></technique_common></bind_material></instance_geometry></node></visual_scene></library_visual_scenes>',
    '<scene><instance_visual_scene url="#Scene"/></scene></COLLADA>',
  }, '\n')
end

local function newPlane(name, kind)
  local material = MATERIAL_NAMES[kind or puddleMaterial]
  if FS:fileExists(MATERIALS) and not scenetree.findObject(material) then loadJsonMaterialsFile(MATERIALS) end
  local path = shapePath(kind)
  if not FS:fileExists(path) then writeFile(path, planeDae(material)) end
  local o = createObject('TSStatic')
  o:setField('shapeName', 0, path)
  o:setField('collisionType', 0, 'None')
  o:setField('decalType', 0, 'None')
  o.canSave = false
  o:registerObject(name)
  return { obj = o, shown = false, kind = kind or puddleMaterial }
end

local function meshObject(i)
  local m = meshes[i]
  if m then return m end
  m = newPlane('sl_puddle_' .. i)
  meshes[i] = m
  return m
end

local function hideMesh(m)
  if m and m.shown then
    local mx = MatrixF(true)
    mx:setPosition(vec3(0, 0, -500))
    m.obj:setTransform(mx)
    m.shown = false
  end
end

-- a plane on the road: p = { x, y, z, sx, sy, dx, dy }, k the size factor; 5 cm above the surface, facing up
local function putMesh(m, p, k)
  local mx = MatrixF(true)
  mx:createOrientFromDirUp(vec3(p.dx, p.dy, 0), vec3(0, 0, 1))
  mx:setPosition(vec3(p.x, p.y, p.z + 0.05))
  m.obj:setTransform(mx)
  m.obj:setScale(vec3(p.sx * k, p.sy * k, 1))
  m.shown, m.lastK, m.owner = true, k, p
end

-- the box the object really covers (once per call site: a plane that did not load has no size)
local function worldBox(m)
  local ok, box = pcall(function() return m.obj:getWorldBox() end)
  if not ok or not box then return 'no world box' end
  local text = tostring(box)
  pcall(function() text = string.format('min %s max %s', tostring(box.minExtents), tostring(box.maxExtents)) end)
  return text
end

-- one plane per puddle: put on the road when drawn first, grown while it is new, shrunk as the road dries (the scale is the only thing that changes after that)
local function updateMeshes()
  for i = 1, math.max(#puddles, #meshes) do
    local p, m = puddles[i], meshes[i]
    if not p then hideMesh(m)
    else
      local f = rules.puddleAlpha(wet, os.clock() - p.born) / 0.8           -- 0..1 (fade in over 6 s, follows the wetness)
      if f < 0.03 then hideMesh(m)
      else
        m = meshObject(i)
        local k = 0.6 + 0.4 * f                 -- (at least 60 % of its size from the start: a puddle is 2-4 m, a damp patch 7-12 m)
        if not m.shown or math.abs((m.lastK or 0) - k) > 0.02 or m.owner ~= p then
          putMesh(m, p, k)
          if stats.drawn == 0 then
            log('I', TAG, string.format('puddle planes: first one put at %.0f, %.0f, %.2f (scale %.1f x %.1f, material sl_puddle %s, world box %s)', p.x, p.y, p.z + 0.05, p.sx * k, p.sy * k,
              tostring(scenetree.findObject('sl_puddle') ~= nil), worldBox(m)))
          end
          stats.drawn = stats.drawn + 1
        end
      end
    end
  end
end

-- for a game test: one 4 m puddle on the ground 6 m in front of the player's car, at once; returns where it is and the box it covers
local debugMesh
function M.puddleNear(kind)
  kind = MATERIAL_NAMES[kind] and kind or puddleMaterial
  local v = getPlayerVehicle(0)
  if not v then return 'no player vehicle' end
  local pos, dir = v:getPosition(), v:getDirectionVector()
  local x, y = pos.x + dir.x * 6, pos.y + dir.y * 6
  local z = groundZ(x, y, pos.z + 12) or pos.z
  if debugMesh and debugMesh.kind ~= kind then pcall(function() debugMesh.obj:delete() end) debugMesh = nil end
  if not debugMesh then debugMesh = newPlane('sl_puddle_debug_' .. kind, kind) end
  local len = math.sqrt(dir.x * dir.x + dir.y * dir.y)
  local p = { x = x, y = y, z = z, sx = 4, sy = 4, dx = dir.x / len, dy = dir.y / len }
  putMesh(debugMesh, p, 1)
  local box = worldBox(debugMesh)
  log('I', TAG, string.format('puddleNear(%s): a 4 m plane at %.1f, %.1f, %.2f (the road under it %.2f, the car at %.2f); world box %s; material %s %s', kind, x, y, z + 0.05, z, pos.z, box, MATERIAL_NAMES[kind], tostring(scenetree.findObject(MATERIAL_NAMES[kind]) ~= nil)))
  return { x = x, y = y, z = z + 0.05 }, box
end

local textureChecked = false
local meshTimer, meshErrLogged
local function checkTexture()
  textureChecked = true
  local found = {}
  for _, path in ipairs({ '/' .. PUDDLE_TEX, PUDDLE_TEX }) do
    local ok, there = pcall(function() return FS:fileExists(path) end)
    found[#found + 1] = path .. '=' .. tostring(ok and there)
    if ok and there then textureChecked = 'found' end
  end
  if textureChecked ~= 'found' then puddleMode = 'prism' end
  log(textureChecked == 'found' and 'I' or 'W', TAG, 'puddle texture: ' .. table.concat(found, ', ') .. (textureChecked == 'found' and '' or ': not found, drawing flat shapes instead'))
end

-- which material the real puddles use ('map', 'alpha' or 'opaque'), for a game test; the planes are made again
function M.puddleMaterial(kind)
  if MATERIAL_NAMES[kind] then
    puddleMaterial = kind
    for _, m in ipairs(meshes) do pcall(function() m.obj:delete() end) end
    meshes = {}
  end
  return puddleMaterial
end

function M.puddleMode(m) if m == 'prism' or m == 'decal' or m == 'mesh' then puddleMode = m textureChecked = true end return puddleMode end

-- a puddle as three flat bars turned 60 degrees apart (a rough hexagon), drawn with the debug drawer
local function drawPrisms(p, alpha)
  local c = ColorF(0.13, 0.14, 0.16, math.min(0.75, alpha))
  local half = p.sx * 0.5
  for k = 0, 2 do
    local a = math.atan2(p.dy, p.dx) + k * math.pi / 3
    local ux, uy = math.cos(a) * half, math.sin(a) * half
    pcall(function()
      debugDrawer:drawSquarePrism(vec3(p.x - ux, p.y - uy, p.z), vec3(p.x + ux, p.y + uy, p.z), Point2F(0.01, p.sy * 0.55), Point2F(0.01, p.sy * 0.55), c)
    end)
  end
end

function M.onPreRender()
  if #puddles == 0 or wet < 0.15 then return end
  if puddleMode == 'mesh' then return end      -- (the planes are moved from onUpdate, nothing to draw here)
  if not textureChecked then checkTexture() end
  if puddleMode == 'prism' then
    local now = os.clock()
    for i = 1, #puddles do
      local p = puddles[i]
      local alpha = rules.puddleAlpha(wet, now - p.born) * (p.damp and 0.35 or 1)
      if alpha > 0.02 then drawPrisms(p, alpha) stats.drawn = stats.drawn + 1 end
    end
    return
  end
  if not (Engine and Engine.Render and Engine.Render.DynamicDecalMgr) then return end
  local now, idx = os.clock(), 0
  for i = 1, #puddles do
    local p = puddles[i]
    local alpha = rules.puddleAlpha(wet, now - p.born) * (p.damp and 0.35 or 1)
    if alpha > 0.02 then
      idx = idx + 1
      if idx > poolSize then
        pool[idx] = { texture = PUDDLE_TEX, position = vec3(0, 0, 0), forwardVec = vec3(1, 0, 0), color = ColorF(1, 1, 1, 1), scale = vec3(1, 1, DEPTH), fadeStart = 80, fadeEnd = 100 }
        poolSize = idx
      end
      local e = pool[idx]
      e.position:set(p.x, p.y, p.z)
      e.forwardVec:set(p.dx, p.dy, 0)
      e.scale:set(p.sx, p.sy, DEPTH)
      local q = math.floor(alpha * 20 + 0.5)
      e.color = colors[q] or (function() colors[q] = ColorF(1, 1, 1, q / 20) return colors[q] end)()      -- (a handful of cached colours, nothing allocated per frame)
    end
  end
  if idx > 0 then
    Engine.Render.DynamicDecalMgr.addDecals(pool, idx)
    if stats.drawn == 0 then log('I', TAG, 'the decal manager is drawing puddles: ' .. idx .. ' this frame (texture ' .. PUDDLE_TEX .. ')') end
    stats.drawn = stats.drawn + 1
  end
end

----------------------------------------------------------------------------------------------

-- the level's rain is a box of drops at a fixed place (WCUSA's WCA_rain sits ~100 m from where you drive): it follows the camera (followCam where the object has it,
-- and moved to the camera each frame as well)
local followLogged = false
local function followRain()
  local rain = first('Precipitation')
  if not rain then return end
  local ok, cam = pcall(function() return core_camera and core_camera.getPosition and core_camera.getPosition() end)
  if not (ok and cam) then return end
  if not followLogged then
    followLogged = true
    local f, at = nil, nil
    pcall(function() f = rain:getField('followCam', 0) at = rain:getPosition() end)
    pcall(function() rain:setField('followCam', 0, 'true') rain:setField('boxWidth', 0, '70') rain:setField('boxHeight', 0, '70') end)
    log('I', TAG, string.format('rain follows the camera: followCam was %s, the rain stood at %s, the camera is at %s', tostring(f), tostring(at), tostring(cam)))
  end
  pcall(function() rain:setPosition(vec3(cam.x, cam.y, cam.z)) end)
end

function M.onStreetLegalStarted() lastKey = nil sync() end
function M.onStreetLegalPhase() sync() end
function M.onStreetLegalNewDay() sync() end

function M.onUpdate(dtReal)
  if not career() then return end
  if not baseline or not lastKey then sync() end
  dtReal = dtReal or 0
  if target and blendT < 1 then
    blendT = math.min(1, blendT + dtReal / BLEND_SECONDS)
    current = rules.blend(blendFrom, target, blendT)
    applyTimer = applyTimer + dtReal
    if applyTimer > 0.2 or blendT >= 1 then applyTimer = 0 applySky(current) end      -- (the objects are applied a few times a second, not every frame)
  end
  wet = rules.wetStep(wet, target and target.wet or 0, dtReal)
  if current and (current.drops or 0) > 0 then followRain() end
  updatePuddles(dtReal)
  if puddleMode == 'mesh' then
    meshTimer = (meshTimer or 0) + dtReal
    if meshTimer > 0.25 then meshTimer = 0 local ok, err = pcall(updateMeshes) if not ok and not meshErrLogged then meshErrLogged = true log('E', TAG, 'puddle planes: ' .. tostring(err)) end end
  else
    for _, m in ipairs(meshes) do hideMesh(m) end
  end
  tintTimer = tintTimer + dtReal
  if tintTimer > 0.5 then
    tintTimer = 0
    local amount = current and current.tint or 0
    if amount > 0.02 then applyTint(amount) end
    if wet >= 0.15 and os.clock() - lastStatsLog > 15 then
      lastStatsLog = os.clock()
      log('I', TAG, string.format('puddles: %d standing (wet %.2f); tries %d, no surface %d, not flat %d, no road %d, placed %d, frames drawn %d', #puddles, wet, stats.tries, stats.noSurface, stats.notFlat, stats.noRoad, stats.placed, stats.drawn))
    end
  end
  gripTimer = gripTimer + dtReal
  if gripTimer > 2 then gripTimer = 0 pushGrip() end
end

-- for a game test: put the weather in this state at once (no blend), e.g. sl_weather.debugForce('rain', 'heavy')
function M.debugForce(id, level)
  readBaseline()
  stateId, levelId = id or 'rain', level or 'medium'
  local st = rules.resolve(stateId, levelId)
  if st.id == 'rain' then lastRain = st end
  target = { drops = st.drops, cloud = st.cloud, fog = st.id == 'clear' and baseline.fog or st.fog, grip = st.id == 'rain' and 1 or st.grip, wet = st.wet or 0, tint = st.tint or 0,
    cirrus = st.cirrus or baseline.cirrus, density = st.density or baseline.density, speed = st.speed or 1 }
  current, blendT = rules.blend(current, target, 1), 1
  wet = target.wet
  M.lastLoggedDrops = nil
  applySky(current)
  return stateId, levelId
end

-- the numbers a game test looks at: what the objects say now
function M.diagnose()
  local rain, cloud, info, sky = first('Precipitation'), first('CloudLayer'), first('LevelInfo'), first('ScatterSky')
  local out = { state = stateId, level = levelId, wet = wet, puddles = #puddles, stats = stats,
    rain = rain and { numOfDrops = rain.numOfDrops, numDrops = rain.numDrops, minSpeed = rain.minSpeed, maxSpeed = rain.maxSpeed } or false,
    cloud = cloud and { coverage = cloud.coverage, cirrusCoverage = cloud.cirrusCoverage, cirrusDensity = cloud.cirrusDensity } or false,
    fog = info and info.fogDensity or false, tint = current and current.tint, sunScale = sky and sky:getField('sunScale', 0) or false, fogScale = sky and sky:getField('fogScale', 0) or false }
  log('I', TAG, 'diagnose: ' .. (dumps and dumps(out) or tostring(out)))
  return out
end

local function clearMeshes()
  for _, m in ipairs(meshes) do pcall(function() m.obj:delete() end) end
  meshes = {}
  if debugMesh then pcall(function() debugMesh.obj:delete() end) debugMesh = nil end
end

local function reset()
  clearMeshes()
  baseline, current, target, lastKey, blendFrom = nil, nil, nil, nil, nil
  wet, puddles, lastRain, followLogged = 0, {}, nil, false
end

function M.onStreetLegalStopped()
  if baseline then applySky(baseline) end
  local v = getPlayerVehicle(0)
  if v and v:getJBeamFilename() ~= 'unicycle' then v:queueLuaCommand('if slCar and slCar.setGrip then slCar.setGrip(1) end') end
  reset()
end

function M.onClientEndMission() reset() end

return M
